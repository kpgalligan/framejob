# Road map "creator-jobs" — the jobs that send creators elsewhere

**Opened 2026-11-01** (CJ0a), when the owner answered CJ0a's eight questions ("6. ReelCore.swift
should be extended to multiple files. Accept all other recommendations."): CJ0a recorded the
owner's answers below as CJ-1…CJ-9 with the bets' scope-level decisions, rewrote spec §1 and §2,
and made the two spec splits (CJ0a's record). The brief is `designs/creator-survey.md`: its "The
bets" (lines 173–356) and the market sections they cite. The worktree is
`.claude/worktrees/creator-jobs`, branch `worktree-creator-jobs`, cut from main at `d0661e5d`.
Decisions go in a new `designs/spec/11-decisions/creator-jobs.md` (one series, continued in
`creator-jobs-2.md`, then `creator-jobs-3.md`, then `creator-jobs-4.md`, each past about 500
lines), each with its row in `11-decisions/README.md` and that file's Lines cell. This file holds
the plan and, as phases land, each phase's record. Line counts and line numbers are `wc -l` and
`grep -n` at `d0661e5d` (main, 2026-11-01); a phase re-reads them at its start.

## Goal

Frame Job finishes video better than most creator tools: its audio chain, colour and HDR, codecs and
an MCP surface over the whole editor (survey, "What Frame Job has"). It loses creators earlier, at
six jobs that now define a creator editor. After this road map each is a command that runs on the
Mac, lands as ordinary undo steps on a real timeline, and has an MCP tool that runs the same
planner:

1. **The Transcript tab (TX).** The timeline read as words, in timeline order. Selected words are
   deleted on every unlocked track as one step; cut words stay greyed and come back with Restore
   Words. A review pass strikes long pauses, fillers (where an AssemblyAI transcript exists),
   retakes, restarts and repeats, for the person to keep or remove in one step.
2. **Screen recordings with the cursor as data (CU).** The recorder saves the cursor's path, images,
   clicks, scrolls and (opt-in) shortcuts beside the movie, and the editor draws the cursor as part
   of the screen clip's layer. Auto Zoom, shortcut overlays, sped-up typing and motion blur follow,
   each as ordinary actions and clips, and the recorder can run them on landing.
3. **Make Vertical Version (VR).** A 9:16 or 1:1 copy of a finished edit, each picture following the
   face, person or salient region Vision found on the Mac (the cursor in a recording made after CU,
   the speaker in a two-shot after SW), as eased x, y and scale actions; captions re-paged and
   graphics re-laid. Linked versions in one project are designed and asked.
4. **Find Clips (FC).** A long recording analysed on the Mac (sentences, speakers, loudness,
   laughter, applause, cheering), ranked by Claude on the person's key with a stated reason per
   moment and no score, and made into saved, captioned, vertical shorts on the Export Queue.
5. **Switch by Speaker, and every audio track (SW).** A program track of shots cut to whoever is
   speaking, judged on each microphone against its own level; Switch Angle; an Angle Viewer and
   switching while playing; a one-microphone mode from faces. Every audio track and channel of a
   file played, measured and transcribed.
6. **Camera cutout and layouts (CO).** Remove Background on a camera clip from Vision's person
   masks, Text Behind Subject, camera layouts switched at the playhead (corner, side by side,
   stacked, camera full, screen only), the same at record time, and the camera hidden while silent.

The shared phases (CJ) give a person two things directly — every command that would send to Claude
or AssemblyAI greyed without its key, with a tooltip saying which key and where; and Clip ▸ Split at
Shot Changes and File ▸ New Project from Range… — and give the bets one key gate, one analysis lane,
store, reader and sheet, a decided clip ceiling, and the files at the cap cut once before three
lanes reach for them.

## What it delivers first

The lead segment is people who record themselves talking: talking-head YouTube and screen tutorials
(TX, CU, CO). Repurposing to shorts comes next (VR, FC), then video podcasts (SW).

- **The baseline.** When TX1 starts, the owner cuts T1 (a talking head, sample S-TH1) and T2 (a
  screen tutorial, S-ST1) in that day's build, to a state they would publish, and records every
  point where they left Frame Job or gave up (CJ-5).
- **The checkpoint, after TX3.** The owner reads T1 as text in the Transcript tab, follows it while
  it plays, clicks a word to seek, selects words and presses ⌫ to cut them on every unlocked track
  as one step "Delete Words". They cut T1 again this way; the verdict is recorded before TX4 starts,
  and lane A builds CJ5a meanwhile.
- **Then the rest of the tab.** TX5 greys cut words and restores them; TX6 and TX7 strike pauses,
  fillers and retakes for review. TX8 is the trial's closing run.
- **Beside it, lane B (T2's kind of video).** Every screen recording saves its cursor (CU1b), the
  editor draws it (CU3c), a Cursor section restyles it (CU4), Auto Zoom plans zooms at clicks and
  typing (CU7), shortcut overlays (CU8), Speed Up Typing (CU9b), and all of it on landing (CU10).
- **Beside it, lane C (the camera).** Clip ▸ Split at Shot Changes proves the analysis lane (CJ2b);
  then Remove Background (CO3), cleaner edges (CO4) and Text Behind Subject (CO5).
- **Then shorts:** Make Vertical Version (VR3, VR4), Find Clips and Make Shorts (FC7a–FC9); camera
  layouts at the playhead and at record time (CO6–CO8). **Then podcasts:** Switch by Speaker (SW2b),
  every audio track (SW3a–SW7b), the Angle Viewer (SW9a, SW9b).

## The owner's answers (2026-11-01)

> "Add all: 1-6. Remove all explicit non-goals. The recorder can ask for input monitoring.
> Anything that requires significant AI should require that the user has supplied a key.
> Otherwise disable. "Cutting one real video per lead segment in Frame Job alongside the first
> bet" OK. Create a full design, then we'll compact and begin."

How each is applied — the orchestrator's reading, recorded at CJ0a. Each line is a default the owner
can change.

- **"Add all: 1-6"** is all six bets of the survey's "The bets", in one road map (CJ-2), led by
  people who record themselves talking (survey decision 1's recommendation). The bets are read as
  the survey wrote them, so bet 1 carries survey decision 3's amendments of TR-3, AI-6 and W-9
  (TX-70) and bet 2 its `recording.md` amendments (CU-1, CU-2); that is the orchestrator's reading,
  not the owner's words, and CJ0a's question 7 confirms it. Bet 3 is read as the copy first and
  linked versions as well (its "L" effort), which CJ0a's question 8 confirms. The survey's next
  tier (lines 358–369) and "Not worth chasing" (371–391) are not built here, and are neither in nor
  out.
- **"Remove all explicit non-goals"** answers survey decision 2. CJ-1 lifts every exclusion spec
  §1's non-goal paragraph names (`designs/spec/01-what-this-is.md:13–40`) and its bar sentence
  (`:9–11`), and §2's "Left out" list (`02-six-ideas.md:24–26`):
  - **Lifted:** multicam; grading beyond per-clip controls (already in by GR-1) and the features
    once marked not wanted (GR-20, GR-27…GR-30); a plugin system and §1's clause "nothing else is
    scriptable" (G-1); §1's clause keeping third-party Audio Unit hosting out (AU-2); motion blur;
    stabilisation; optical-flow retiming; auto-reframe; ML or heavy pixel work outside the
    compositor's one pass; callouts and reconstructing afterwards what the recorder saw
    (`recording.md`, CAM-1); any platform but macOS; and §2's pointer effects, templates, publishing
    to YouTube or Vimeo and a stock-media library.
  - **Lifting makes a thing allowed, not scheduled.** This road map builds, from that list: multicam
    (SW, as a program track over angle tracks, SW-3), auto-reframe (VR-1), ML outside the one pass
    (Vision boxes and person masks made offline and drawn in the one pass: CJ2a, CJ3, VR1, CO1),
    reconstructed callouts (CU's cursor, zooms and keystroke overlays) and motion blur on zooms and
    the cursor (CU11, spike-gated). Nothing else on the list is built.
  - **Decisions that implement a non-goal stand as current design** until a phase that needs
    otherwise amends them in writing, before its code: G-1 (a graphic is a source; nothing else
    becomes scriptable here), AU-2 (no third-party Audio Unit is hosted here), R5-1 (effects are
    closed vocabularies), and `recording.md`'s "a recording is ordinary media" (which CU-2 amends at
    CU0a). Their amendment lines say "§1's clause lifted; the decision stands as current design"
    (CJ0a's table).
  - GR-20 and GR-27…GR-30 were the owner's own "not wanted"; CJ0a asks the owner to confirm the
    literal reading (question 5).
- **"The recorder can ask for input monitoring"** answers survey decision 4 (CJ-4). Only the
  recorder panel asks, and only when the person turns on Record shortcuts and presses Record;
  `record_screen` only reads the grant. Capture is opt-in per recording, records each ⌘ or ⌃
  shortcut by name and only the TIME of every other key press, nothing while any app holds secure
  input, and shows a mark in the menu bar while on (CU-3, CU-7). It is the recorder's fourth grant,
  after Screen Recording, Microphone and Camera.
- **"Anything that requires significant AI should require … a key. Otherwise disable."** answers
  survey decisions 6 and 7 (CJ-3). Its exact reading:
  - A feature needs a key when it sends to a language model or a cloud model: Claude through the
    person's Anthropic key (Frame Job ▸ Settings… ▸ Assistant, AI-8) or AssemblyAI through its key
    (Settings ▸ Transcription, R6-5).
  - Without the key, every control that would make a NEW request is disabled, its tooltip CJ-11's
    sentence naming the key and where it is set; every tool call that would send refuses with that
    sentence, at the point it would send — after its own earlier refusals and after any answer it
    can give from a cache.
  - "Present" is a stored non-empty key, or the proof's environment variable, in R6-5's order.
    Whether a key is valid is the service's answer to a request and never decides a control.
  - A result already paid for stays usable without a key: cached AssemblyAI transcripts serve
    captions (R6-16), Remove Filler Words, the review's filler strikes and a short's filler cut; a
    cached Find Clips ranking is read at no cost.
  - No on-device fallback: Apple FoundationModels is not used, and filler detection stays
    AssemblyAI's (TR-7 stands).
  - Not "significant AI" and never gated: Vision, Sound Analysis, Speech (`SpeechEngine`), Silero
    VAD and `AUSoundIsolation` — Apple frameworks and models that run today without a key.
  - It applies to the shipped features too (Remove Filler Words, Generate Captions' AssemblyAI
    engine, `transcribe`'s cloud engine, `transcribe_for_fillers`, the Assistant), through one
    implementation, CJ1's `ModelKeys`.
- **"Cutting one real video per lead segment … alongside the first bet. OK."** answers survey
  decision 9 (CJ-5). T1 (talking head, S-TH1) and T2 (screen tutorial, S-ST1) are cut three times:
  the baseline when TX1 starts, the checkpoint after TX3 (T1 by deleting words), and the closing run
  at TX8. Each is recorded in "The owner's trials" below and the verdict under CJ-5, as grading's
  trial was under GR-1. Later segments have trials of their own (CU12, VR-38, FC-91, SW-29).
- **"Create a full design, then we'll compact and begin"** is this file. After compaction the
  orchestrator starts at CJ0a, which asks CJ0a's eight questions first.
- **Survey decisions not answered in words:** 3 is read from "Add all" (above) and confirmed by
  CJ0a's question 7; 5 (a vertical copy or linked versions) is CJ0a's question 8, answered yes
  (2026-11-01); 8 (the multi-stream 4K and multi-hour measurement) is CJ0a's question 4, answered
  yes (2026-11-01), run as SW-S2 in SW0; 10 (positioning) is not a build question. Decision 3's AI-10 and W-10 amendments belong to
  the next tier; no bet needs them.

## The orchestrator's defaults (each one the owner can change)

- **Working arrangement.** `.claude/worktrees/creator-jobs` (branch `worktree-creator-jobs`) is the
  integration branch. Each phase is one litecode pipeline (design → adversary → implement → review →
  fix), handoff dir `~/.claude/litecode/framejob/cj-<phase id lowercased>` (`cj-tx2a`, `cj-cu0b`,
  …), built in a lane worktree of its own, gated (`make gate`) and committed there, then rebased
  onto the integration branch by one serialized integrator, one landing at a time, and gated again.
  Each landing is merged into main by fast-forward (CJ0a's question 1, answered by the owner
  2026-11-01, since other work continues on main). Commits stage only the phase's own files (other sessions share the
  tree).
- **Lanes: at most three, split by the files they touch.** **A, words:** the key gate, the
  Transcript tab, New Project from Range, Find Clips, then every audio track. **B, recorder and
  placement:** the cursor and the recorder, then camera layouts, hide while silent and link groups.
  **C, pictures:** the analysis lane, the camera cutout, faces, Make Vertical Version, the clip
  ceiling, then the switch. A lane whose next phase needs another lane's unlanded phase waits; it
  never builds against an unlanded one. The integrator may move a phase to an idle lane when its
  dependencies have landed and no running phase holds its files, and records the move.
- **Collisions and renumbering, at each landing.** A format bump is provisional ("38p") until its
  phase lands; the integrator renumbers it, its `schema_vN.rs` and its `format_history.rs` paragraph
  when another lane landed one first. Decision IDs are renumbered only when two phases claimed one.
  JOB numbers are renumbered inside their block. The integrator also reconciles the pinned counts
  (CJ-8 (g)), the screen catalog's numbers, the spec index's Lines cells, `UIMenuTable.swift` and
  `capture_spike/inventory.json` rows, `menus-and-shortcuts.md` (a key equivalent is checked for a
  clash, CJ-8 (e)), and the `LayerUniforms` size pins (CJ-8 (b)); and if the unmerged tutorials
  branch reaches main meanwhile, the later of the two adds `TutorialTargets` rows for the new tabs,
  items and windows and reconciles `v2_menu.py` once (Risks).
- **IDs (CJ-7).** Phases are `XXn`, XX one of TX (transcript), CU (cursor and recorder), VR
  (vertical), FC (find clips), SW (switch by speaker), CO (cutout and layouts) and CJ (shared); a
  phase split by size is `XXna`, `XXnb`…, sharing its number's block, and a lettered phase split
  again takes a digit (`CO2a1`, `CO2a2`), its letter alone still naming both halves (a phase that
  depends on "CO2a" waits for both). Phase XXn owns decisions
  XX-n0…XX-n9; XX0 owns XX-1…XX-9, and a bet with no zero phase records its scope-level decisions at
  CJ0a under its own prefix (VR-1…VR-7, TX-70; SW's SW-3 sits in SW0's block). CJ0 owns CJ-1…CJ-9.
  Spikes are XX-S1, XX-S2…. Manual checks are `JOB-n` in blocks of ten: CJ 1–9, TX 10–19, CU 20–29,
  VR 30–39, FC 40–49, SW 50–59, CO 60–69, then 70 onward for a bet that needs more. The checkpoint
  after TX3 is CP1.
- **Agent parity.** Every user-visible edit has its MCP mirror: a handler (a row in
  `AgentServer+CreatorJobs.swift`'s `creatorHandlers`, CJ-8 (d)), a catalog entry declaring `scope`,
  and a comment naming the UI path. A command that is a composite of ops lands as one undo step
  through `performGroupedEdit`, and its tool runs the same planner; a rule that must hold inside the
  core makes it an op (CJ-8 (f)). Every new property is a `set_video` or `set_audio` key, every
  answer readable through `get_project` or the tool's own answer.
- **Proof currency.** The repo's: placements read back through `get_project`, PNGs compared byte for
  byte, exports decoded to PCM and measured by the proof's own arithmetic, planners on canned
  analyses (CJ-26) so their rows are byte-exact on any Mac, Vision's rows on fixtures and samples
  against tolerances fixed before the run, and a proof compared against the cache, never a
  recomputation (E9's rule). The recorded run of each phase is against Release, after the gate's
  `make app`. Mutants target each phase's decisions, about one per branch, threshold, refusal or
  ordering, run once on the final instrument. What only a person can judge is a JOB row in
  `docs/manual-checks.md`.
- **The key rule in practice.** Every keyed control or tool is a row of `ModelKeys.keyed` (CJ1),
  tests presence only through `ModelKeys.present`, refuses in `ModelKeys`' sentence at the point it
  would send, and its catalog description names its key (the parity check's sixth part, CJ-13).
  Proofs run with `-RCSecretFolder` on an empty scratch folder and the variables unset, or a dummy
  key against `assemblyai_fake.py` or `anthropic_fake.py`; the owner's stored keys are never read
  (R6-9, AI-13). `.secrets/` is never opened.
- **Spend.** Only four runs spend money, each behind `--live --cap` and the month's budget (P-3,
  P-6), its dollars reported: TX7's prompt eval (`assistant_prompt_eval.py --live --cap 1.00`, once,
  after TX3–TX7 have rewritten the prompt's "Cutting words" paragraph, since TX8 and JOB-15 then use
  the hand-off with a real key and the live-spend rule runs a paid proof when a change is likely to
  break what it tests), FC-S2 (Anthropic, cap $3.00), FC-S3 (AssemblyAI, cap $0.50) and FC8a's
  prompt eval (`--live --cap 1.00`, for FC's clips row). TX-S4's AssemblyAI read (about a cent, cap
  $0.05) runs only if the owner allows it: TX7's question 3.
- **Samples.** The owner's recordings live in `tools/proof/media/creator/` (gitignored), with a row
  each in `samples/README.md`; they are never committed, since they carry the owner's face and
  voice, and are sent to a cloud service only by a spike that names it, with a guest's recordings
  sent only with the guest's agreement. No phase waits for a sample: a row that needs a missing one
  skips by name and is owed in the phase's record.
- **Persisted fields** carry serde defaults, are written only when set, and bump the format
  (`core/CLAUDE.md`); an older project opens unchanged and renders byte-identically.
- **Size.** A file at the ~600-line cap (400 for a file created after the rule) gives something up
  before it takes anything on, as a pure move landed and gated alone; frozen files take wiring only.
  A phase is sized for one litecode pipeline; effort is never measured in lines, and no feature has
  a line budget.
- **Long or costly runs** (SW-S2's 34 GB fixture, a three-hour file, FC8b's thirty shorts) run only
  behind their own flags and after the owner's yes. A single flaky failure is re-run once before any
  investigation; a soak over 30 minutes is asked first.

## How it fits the tree

At `d0661e5d`.

**Where the non-goals are written.** Only in the spec and in §11 entries that cite it:
`designs/spec/01-what-this-is.md` (47 lines: "Mac only" at 7, the bar sentence at 9–11, the non-goal
paragraph at 13–40), `02-six-ideas.md` (26 lines; "Left out" at 24–26), `designs/spec/README.md:20`
(the index row; `spec_index_proof.py` checks its Lines cells in `make test`), the §11 entries
`recording.md:6–15`, `camera-recording.md:15–40` (CAM-1), `graphics.md:6–17` (G-1), `audio.md:52–60`
(AU-2), `grading.md:27–40` (GR-1), `effects-motion.md:6–11` (R5-1), `grading-3.md:466` (GR-20) and
`grading-4.md:99–109` (GR-27…GR-30), and the §11 index rows that restate them
(`designs/spec/11-decisions/README.md`): the file rows for `recording.md` (:16, "what is in and
out") and `camera-recording.md` (:44, "callouts still out"), the `recording.md` decision row (:70,
"camera recording and callouts stay OUT"), GR-1 (:326), GR-20 (:345), GR-27…GR-30 (:352–355, "not
wanted"), CAM-1 (:482, "callouts stay OUT") and AU-2 (:512, "third-party Audio Unit hosting stays
out under the plugin non-goal"). `README.md`, `docs/guide/` and the three `CLAUDE.md` files hold
none; `CONTEXT.md:37,57`'s "plugin" is vocabulary and stays; `designs/adr/` is history.

**Keys: two keys, two stores, ten `credential` calls, two change notifications, three behaviours.**
- `SecretStore.swift` (235): `FileStore` (`0600`) and `MemoryStore`; the files are `assemblyai-key`
  and `anthropic-key` in `~/Library/Application Support/Frame Job/`.
- `AssemblyAIConfiguration.swift` (179): `store()` :135 (R6-9's `-RCSecretFolder` and endpoint
  isolation), `credential` :150 (the file, then `RC_ASSEMBLYAI_KEY`). `AssistantConfiguration.swift`
  (216): `store()` :78, `credential` :97 (then `ANTHROPIC_API_KEY`).
- The two keys post two different notifications. The AssemblyAI pane's is
  `SettingsWindowController.didChangeNotification` (`"FrameJobSettingsDidChange"`,
  `SettingsWindowController.swift:72`, 463 lines), posted after Save :391, Remove :405 and the
  region :416, and observed only by `TranscribeSheetController.swift:355`. The Anthropic key's is
  `AssistantConfiguration.didChangeNotification` (:138), posted by `AssistantSettingsPane.swift:359`
  and observed only by `EditorViewController+Assistant.swift:67`. The Remove Filler Words sheet
  observes neither.
- Of the ten `credential` calls, four only test presence
  (`FillerSheetController+Transcribe.swift:85`, `TranscribeSheetController+Cloud.swift:221, :250`,
  `EditorViewController+Assistant.swift:170`), five read the key to send it
  (`FillerSheetController+Transcribe.swift:144`, `TranscribeSheetController+Cloud.swift:292`,
  `AgentServer+Fillers.swift:143`, `AgentServer+CloudCaptions.swift:119`,
  `AssistantSession.swift:107`), and one words Settings' status line
  (`AssistantSettingsPane.swift:217`). The sheets take an injected store and environment
  (`FillerSheetController.swift:37, :98`, `TranscribeSheetController.swift:91, :170`), which the
  probes fill with `MemoryStore`s.
- Remove Filler Words is enabled whenever a clip plays sound from a media file
  (`FillerSheetController.swift:301–305`); without a key its Transcribe rows are disabled with "No
  AssemblyAI API key is set — Frame Job ▸ Settings…". `transcribe_for_fillers` reads the credential
  only after its own refusals and after answering `ready: true` for a media that already has a
  filler transcript (`AgentServer+Fillers.swift:77–84`, `:125–147`; the sentence at
  `CloudTranscriber.swift:56–62`). Generate Captions' Start is enabled without a key only when R6-16
  admits the batch (`TranscribeSheetController+Cloud.swift:216–253`). The Assistant without a key
  shows "Add your Anthropic API key in Settings to use the assistant." (`AssistantView.swift:25`,
  `:247–250`); View ▸ Assistant (⌃⌘A) is always enabled. AI-1: the app never calls Anthropic; the
  bundled helper (`agent/`, byte-identical with Rasterize's but for NM-10's three lines) does.

**Words and cuts.**
- AssemblyAI words are cached verbatim per media (`MediaTranscript.swift`, 381; R6-10's mapping
  `words(for:in:)` :336, a ramp through S⁻¹ at :367). On-device words are cached per media and
  language as runs of source ticks, a hit being one stored run containing the asked span
  (`DeviceTranscriptCache.swift`, 209, `lookup` :121, `store` :146; TR-14); only `get_transcript`
  reads it (`TranscriptReader.swift`, 238; `AgentServer+Transcript.swift:29`, off main).
- `Transcriber.jobs` (`Transcriber+Jobs.swift:98`) is the one gate for which clips have words; a
  nest clip fails its first test, and `NestSnapshot.clips` (`ProjectSnapshot.swift:1227`) holds a
  nest's clips. The plan's audio segments are the heard instances, already clipped to every
  enclosing nest clip (`evaluate.rs` `Segment::to_json` :178, `plan.rs` `audio_segment` :199, 294
  lines), but carry no instance path (`nest.rs` `Instance::path` :131).
- On-device word ranges tile the audio (a 1.57 s silence showed as 0.30 s) and start 270 ms early;
  AssemblyAI's run 60 ms late (`CaptionPages.lead(for:)`, `CaptionPages.swift:69`). The Silero voice
  cache is per media on a 32 ms grid (`MediaSpeech.swift`, 50). `SpeechEngine.transcribe` blocks at
  `.userInitiated` (`SpeechEngine.swift:112`, 399 lines); the guide says "a few seconds per minute
  of speech" (`docs/guide/cleanup-tools.md:131`) with no long run recorded.
- `ripple_delete_ranges` (`core/src/edit_time.rs:307`, 595 lines) snaps and merges, clears every
  unlocked track through `split_under_playhead` (`edit_clip.rs:504`), closes holes right to left,
  leaves markers. `insert_time` (:454) moves markers, so the two are not inverses; no op restores a
  cut. `split_clip` (`edit_split.rs:95`) gives the second half `in + round(clip_t × speed)`.
  `shifted` (`edit_time.rs:91`) leaves a clip straddling the boundary whole.
- `MAX_CLIPS` is 4,096, nested clips counted (`format.rs:27`, `check_caps` :57, `RC_MAX_CLIPS` at
  `framejob_core.h:245`); Swift reads it at `CaptionLayout.swift:176, 288` and
  `CaptionImporter.swift:118`. `RC_FORMAT_VERSION` is 37 (`format.rs:18`, header :240).
- Remove Silences (`SilenceDetector.swift`, 438; walls in `SilenceDetector+Walls.swift:23, :108`)
  and Remove Filler Words (`FillerDetector.swift`, 383; TR-9) answer project spans for one
  `ripple_delete_ranges`; the timeline wash is `TimelineView.candidateSpans` (:43), one slot both
  sheets set and clear (TR-10).
- The assistant's search guide is 1,498 of its 1,500 characters (`assistant_prompt_probe.swift`'s
  F6); a tool added to a row's TOOL list costs no characters (F4).

**The inspector, keys and menus.** `InspectorTab` has four cases (`InspectorTab.swift:19`, 81); the
strip tiles equal widths (`Controls.swift:573–578`) and the inspector is 280–440 pt
(`EditorViewController.swift:25–27`), its width a persisted default no tool sets. `handleEditorKey`
(`EditorViewController.swift:712`) returns false when the first responder is an `NSText` (:713).
`perform_menu_item` refuses a selector with no `UIMenuTable.swift` row, and `v2_menu.py`'s H1 and H2
hold the table, `capture_spike/inventory.json` and the live menu to one another.
`select_inspector_tab`'s tabs are pinned in `tools/proof/v3_tools.py:52`.

**The recorder.** `RecordingSetup.swift` (398 of 400) sets `stream.showsCursor = true` (:223) and
`showMouseClicks` (:224), BGRA only with clicks (:228); `RecordingChoice` (:84–98) has no cursor or
key option; the grants are `// MARK: - The grants` (249–398). `ScreenRecorder.swift` (399 of 400)
adds `ScreenFrameWatch` only with a camera (:265–275); the watch's state is `private`
(`ScreenFrameWatch.swift:50–58`, 173 lines). `RecorderStatusItem.swift` (234, :7–13) has no global
hotkey because it would need Input Monitoring or Accessibility. The panel's eleven
`FrameJobRecording…` keys are persisted in `RecorderPanelController+Rows.swift` (395 of 400) from
:271. `NSCursor.currentSystem` "will always be nil in a future version of macOS" (`NSCursor.h:155`)
but typechecks without a warning today. `SCStreamFrameInfo` carries `DisplayTime`, `ScaleFactor`,
`ContentScale`, `ContentRect`, `DirtyRects` and `ScreenRect`. Input Monitoring's pane is
`x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`. The camera lands in
CAM-10 (3)'s corner by Swift arithmetic (`RecordingLanding+Camera.swift:35–66`, 255).

**Placement, actions, the recipe and the compositor.**
- (★), `canvas(q) = anchor + s·R(θ)·(c + q)`, is solved for a region in `core/src/edit_zoom.rs`
  (467, :38–55); `add_zoom_action` composes `add_action` + `set_action` + `set_action_end`.
  `edit_fit.rs` (61) has `fit_scale` and `fill_scale` (:52). `set_canvas` rescales top-level
  placement but not action end patches (`edit_canvas.rs:58–96`, 251). A nest's canvas is frozen and
  a nest clip folds only x, y, scale, rotation, opacity and crop (`nest.rs:382–394`, 470).
  `MAX_TRACKS` is 64, nests' tracks counted (`format.rs:27–28`).
- No two actions on one clip overlap (`edit_action.rs:63`, 595 lines); `Action {id, start, duration,
  curve, end}` carries no tag (`model.rs:440`); the only zoom test is `ActionBands.isZoom`
  (`ActionBands.swift:37–43`). A split rebases a straddled action (`edit_split.rs:204–246`;
  `state_patch` :40, `narrow_to` :61). `video.motion` moves the drawn layer after the actions
  (`motion.rs:1–30`).
- The one file mapping a FILE time into a clip's time through reversal, speed and ramps is
  `speech_in_clip` (`audio_duck_speech.rs:31–67`, 193 lines); the reversed mirror is app arithmetic
  with one home, `ReverseMirror.swift` (D4-6).
- A layer is the twenty-six keys `RecipeLayer.object()` writes (`recipe_layer.rs:14`, 158 lines); a
  media layer's source is `{kind: "track", track_id}` with no source time (`recipe.rs:464–480`, 547
  lines). `layerSample` (`Compositor.metal:800`, 2,811 lines) is the one source read of the layer
  stage, before `gradeSample`. The layer stage binds `texture(0)`…`texture(3)` (source, matte
  coverage, look, curves; :1902–1906); `LayerUniforms` is 132 floats, 528 bytes
  (`Compositor.metal:381`, `LayerUniforms.swift:245–250`). Mattes resolve per group into
  `texture(1)` (`recipe_matte.rs`, `Compositor+Matte.swift`, `MattePlan.swift`).
- `add_background` makes a "Background" plate and `add_blurred_background` a "Blurred Background"
  copy, each on a NEW back-most track (`edit_background.rs:12, :173–174, :267, :393`, 461 lines);
  the blurred copy refuses a nest clip (:355–400).

**Analysis and offline renders.** `app/Sources` imports no Vision and no SoundAnalysis.
`MediaCacheLane.swift` (78) is the import pass's width-2 lane for audio decodes only (#367).
`MediaCacheLedger.swift` (231) gives one current pass per (package, media) and
`CacheLedger.publish(in:for:_:)` (:171), which never writes during a save and takes a nil pass.
`CacheStamp` and `SpeechStamp` (`MediaCacheFiles.swift:172–197, :249–262`, 452 lines) are the stamps
a new one copies. `RampAudioRenders.swift` (281) is the offline queue's shape: owners, cancel when
unwanted, the export waits (`Exporter.withRampAudio`), `-RCDevRampRenderHold`.
`MediaImporter+ThumbnailSource.swift` (349) draws a log, HLG or PQ strip through a one-clip
composition (`oneClip` :311, `private`) and records its conversion in `ConvertedThumbsStamp`
(:114–157). `BackgroundRender.swift` (116) knows every transport (`transports` :71, `private`). The
E9 spike (`tools/proof/effects_spike/vision_*.swift`, `designs/adr/effects-survey.md:264–285,
326–334`): person masks `.balanced` (512×384) at 10 a second run 4.2–5.5× realtime, accurate
1.6–1.7×; one device is byte-identical, GPU and Neural Engine differ by up to 25 levels; foreground
masks flicker on video; its fixtures read the album covers macOS ships in
`/System/Library/Photos/Resources/FlexAudio/`.

**Audio streams.** `Media` records `has_audio` only (`model.rs:162–192`, 570 lines); `add_media`
treats a known path as an identity (`edit_track.rs:476`). Every reader takes the first audio track:
the builder's `firstTrack` (`CompositionBuilder.swift:423–425`, 546 lines), the renderers
(`Transcriber+Extract.swift:106`, `VoiceRenderer.swift:66`, `RampAudioRenderer.swift:116`,
`IsolationRenderer.swift:109`, `ReverseRenderer.swift:201`, `RampAudioCache.swift:136, :191`), the
four cache passes (`MediaImporter.swift:478, 506, 537, 581`, 589 lines), the 48 kHz copy keyed by
file (`AudioRateCopy.swift:56–70`) and the Matroska index (`container.rs:1–5, :90–94`, 358 lines;
`FFmpegRewrap+Plan.swift:233` maps `0:a:0?`). Caches are per media id. A link is a pair
(`edit_link.rs`, 335; `partner` :153). `AudioSync.swift` (551) reads once and plans purely.

**Documents and the helper.** No op copies a timeline range into a new project; there is no File ▸
Duplicate (`fileMenu()`, `AppDelegate+Menus.swift:119–193`). An untitled document's caches live in
`NSTemporaryDirectory()/FrameJob/<UUID>/` until the first save (`intendedCacheDirectory`,
`ProjectDocument.swift:761–770`). A reverse renders only behind its document's sheet
(`ProjectDocument.swift:908–935`), and the Export Queue captures the reverse resolution at enqueue
without waiting (`ExportQueueController.swift:66–77, :315–330`, 551 lines). A cloud transcript's
file is the only record of a remote id still owed a DELETE (R6-4, R6-11). The helper's requests
carry `TOOL_SEARCH`, effort medium, `fallbacks: "default"`, at most 30 rounds of 32,000 output
tokens (`agent/src/main.ts:32–34, :252–264`); it prices each response (`pricing.ts`) and the app
writes one ledger line per cost event (`AssistantSpend.swift:119`). `AssistantSession.swift` (390)
owns the process plumbing.

**Dispatch and the pinned counts.** The frozen `AgentServer.swift` (807) holds `productOffMainTools`
(:108–113), merged at :115, `productHandlers` (:213), the merge `handlers =
withDevHandlers(productHandlers)` (:335) and `opsWithoutTools` (:342, empty). The counts a new tool
or op moves: `OP_COUNT` 64 (`op_table.rs:90`); `PRODUCT_TOOLS = 106` and `OPS = 64`
(`op_argument_proof.py:149–150`); `TOOLS = 74` and `APP_STATE_TOOLS` (`phase9_proof.py:193, :209`);
root `CLAUDE.md`'s "one hundred and six product tools"; `app/CLAUDE.md`'s "sixty-four op tools";
`ReelOp.documentLevelNames`, which holds NINE names (`ReelOps.swift:171–176`; `app/CLAUDE.md` still
says eight, corrected by the first phase that adds one): `scope.rs`'s `refused_inside` (:178), whose
ten arms are those nine and `add_adjustment_clip`, which `documentLevelNames` lacks (its doc at :172
says "fifty-three" where 64 − 10 is fifty-four); spec §6a's "Ten ops are an error with a scope"
(`06a-edit-operations-shared-rules.md:85`); the dev tools' count (`dev_tools.py`).

**Frozen files, wiring only:** `EditorViewController.swift` (1,079), `TimelineView.swift` (1,704),
`PreviewCanvasView.swift` (1,121), `InspectorViewController.swift` (359), `AgentServer.swift` (807).

### Files at or near the cap, and who pays

Each cut is a pure move, landed and gated alone, diffed line-identical against the base, before the
paying phase edits the file (T16 alone is a small refactor, its row says why). Every range is
`d0661e5d`'s; the paying phase re-reads it with `grep -n` before it moves anything, taking each
item's doc comment with it and leaving the next item's. "Named" is a seam
`designs/adr/app-file-history.md` or `core-file-history.md` already names. A file not listed is paid
by the first phase that must edit it, which names the seam in the history's "Named next cuts".

| File | Lines | Cut | Paid by |
|---|---|---|---|
| `core/src/op_table.rs` | 374 of 400 | T1: `OP_TABLE` (246–362), `OP_NAMES`, `names()` (363–374) → `op_rows.rs`, re-exported; `req`, `opt`, `within`, `op` become `pub(crate)` | CJ0b |
| `core/src/model.rs` | 570 | T2, named: the media types (`// ---- media`, 156–217) → `model_media.rs`, re-exported | CJ0b |
| `core/src/recipe.rs` | 547 | T3, named: the content hash (80–119) → `recipe_hash.rs` | CJ0b |
| `core/src/edit_clip.rs` | 616, over | T4, named: `TITLE_FONT`, `TITLE_CONTENT` (67–72), `Described` (78–84), `add_text_clip`, `add_shape_clip`, `add_described_clip` with their docs (227–366) → `edit_described.rs`; `DEFAULT_CLIP_DURATION` stays, `pub(crate)` | CJ0b |
| `app/Sources/AppDelegate+Menus.swift` | 554 | T5, named and extended: the View menu (`viewMenu`, `trackHeightMenu`, `previewQualityMenu`, 442–526; 528–535 are `windowMenu()`'s doc and stay) → `AppDelegate+ViewMenu.swift`; `viewMenu` loses `private` | CJ0c |
| `app/Sources/CompositionBuilder.swift` | 546 | T6, named: the held last frame (428–519) → `CompositionBuilder+HeldFrame.swift`, carrying the `timeRange` deprecation: its `TYPECHECK_BASELINE` row (`gate.py:87–88`) and root `CLAUDE.md`'s "2 in `CompositionBuilder.swift`" move with it | CJ0c |
| `app/Sources/ProjectDocument.swift` | 1,336, over | T7, named: `// MARK: - Reverse` (827–980) → `ProjectDocument+Reverse.swift`, dropping `private` on `refusedReverseMedia`, `renderingReverseMedia`, `isPresentingReverseSheet` (:364–369) | CJ0c |
| `app/Sources/AgentServer.swift` | 807, frozen | T8: a new `AgentServer+CreatorJobs.swift` (`creatorHandlers`, `creatorOffMainTools`, `withCreatorHandlers`); the frozen file changes its two existing merge lines (:115, :335) | CJ0c |
| `designs/spec/07.9a-agent-tools.md` | 550 | T9: the app-state tools → a new `07.9e-agent-app-state-tools.md` | CJ0a |
| `designs/spec/04.3b-inspector-clip-sections.md` | 520 | T10: "Audio sections" to the end (279–520) → a new `04.3d-inspector-clip-sections-audio-text-shape.md` ("continues §4.3b") | CJ0a |
| `app/Sources/ProjectSnapshot.swift` | 1,454, over | T11: `VideoProps` with its doc (784–895) → `VideoProps.swift`; T12: `// MARK: - Clips` (896–1173, `ClipSource` with its `private enum CodingKeys`, `ClipSnapshot`, `TransitionSnapshot`) → `ClipSnapshot.swift`; T13: `// MARK: - Tracks` (443–505) → `TrackSnapshot.swift`; later `// MARK: - Canvas` (392–442) → `CanvasSnapshot.swift` | CJ0d (T11–T13); VR7a (Canvas) |
| `app/Sources/FrameRecipe.swift` | 417, over its 400 | T14: `RecipeLayerMatte`, `RecipeLayerDissolve`, `RecipeMatteGroup` with `RecipeLayerMatte`'s doc (213–270; `RecipeLayer`'s doc at 272–273 stays) → `FrameRecipe+Mattes.swift` | CJ0d |
| `app/Sources/ReelCore.swift` | 766, over | T15: the media-file wrappers (411–612) → `ReelCore+MediaFiles.swift`, the graphics wrappers (614–739) → `ReelCore+Graphics.swift`, `takeErrorMessage`/`takeString` internal; T15c `rc_agent_string_create` behind `ReelAgentSocket` | CJ0d |
| `app/Sources/MediaImporter.swift` | 589 | T16, the named seam re-scoped (it cannot be a pure move: the `switch result` body, 388–405, holds `break frames`, a labelled break to the loop at :386, and writes the loop's locals): the `.success` arm's tile loop (389–398) becomes `writeTiles` in `MediaImporter+Thumbnails.swift`, the labelled break left in the loop — a small refactor gated alone, not a pure move; later SW-43: the four audio passes (443–588) → `MediaImporter+AudioPasses.swift` | CJ0d; SW4a |
| `app/Sources/ReverseRenderer.swift` | 574 | T17, named: `// MARK: - Settings` (480–574) → `ReverseRenderer+Settings.swift` | CJ0d |
| `app/Sources/RecordingSetup.swift` | 398 of 400 | U1, named: `// MARK: - The grants` (249–398) → `RecordingGrant.swift`, re-aiming `recording_probe.py`'s 10f | CU0a |
| `app/Sources/ScreenRecorder.swift` | 399 of 400 | U2: `captureStarted`, `failStart` (341–399) → `ScreenRecorder+Started.swift` (`refuse`, `private`, stays) | CU0a |
| `app/Sources/RecorderPanelController+Rows.swift` | 395 of 400 | U3: `// MARK: - The choice, persisted and restored` (271–395) → `RecorderPanelController+Choices.swift` | CU0a |
| `app/Sources/AgentCatalog+Recording.swift` | 390 of 400 | U4: `record_screen`'s argument descriptions → `AgentCatalog+RecordingArguments.swift` | CU0a |
| `core/src/actions_clamp.rs` | 405, over its 400 | U5: the grading clamps (`clamp_wheels` … `clamp_level`, 169–272) → `actions_clamp_grade.rs`; `bounded`, `finite_or` (called from the moved clamps) and `clamp_wheels`, `clamp_qualifier` (called from `clamp_video`, :89, :91, which stays) become `pub(crate)`; `clamp_curves` already is | CU0a |
| `app/Sources/EditorViewController+Inspector.swift` | 403, over its 400 | `// MARK: - Commands the inspector made real` (142–370) → `EditorViewController+InspectorCommands.swift` | TX2a |
| `app/Sources/SpeechEngine.swift` | 399 of 400 | `// MARK: - Locales and models` (234–316) → `SpeechEngine+Locales.swift`, only if TX-S1 makes the fill take a priority | TX1 |
| `core/src/edit_action.rs` | 595 | the end-patch door (`prune_removed` with its doc … `key_off`, 99–290) → `edit_action_end.rs` | CO2a1 (VR2b reuses it) |
| `core/src/actions.rs` | 587 | named: `color_json`, `wheels_json`, `video_json` → `actions_json.rs`, only if wiring would pass ~590 | CO2a1 or CO9 |
| `core/src/evaluate.rs` | 559 | `Segment` and its `impl` with `to_json` (127–204; 206–208 are `CompTrack`'s doc and derive and stay) → `plan_segment.rs` | the first of SW3a, SW2c (CO2a1 no longer edits it: no mask track, CO-3) |
| `core/src/format_history.rs` | 371 of 400 | versions 2–24 → `format_history_early.rs` | the bump whose paragraph would pass 400 |
| `app/Sources/AgentCatalog+Properties.swift` | 410, over its 400 | the video patch's clauses and `videoPatchDescription` (23–191) → `AgentCatalog+VideoPatch.swift`, `private` widened | CO2a1 |
| `app/Sources/Exporter.swift` | 598 | `// MARK: - Offline single frame` (478–598) → `Exporter+Frame.swift`, carrying the `copyCGImage` deprecation (:583): its `TYPECHECK_BASELINE` row and root `CLAUDE.md`'s "1 in `Exporter.swift`" move with it | paid by CU3a2 (CO2b does not repeat it) |
| `app/Sources/EditorViewController+SaveFrame.swift` | 399 of 400 | `// MARK: - The save panel's options` (277–399) → `SaveFrameOptions.swift` | CO2b |
| `app/Sources/CaptionLayout.swift` | 581 | `// MARK: - Words into cues` (420–581) → `CaptionCues.swift` | VR4 |
| `app/Sources/Playback.swift` | 592 | named: `setPreviewQuality` and `recompose()` → `Playback+PreviewQuality.swift` | SW0 |
| `app/Sources/ProjectDocument.swift` (after T7) | about 1,182 | `generateCaches()` with its doc (811–826) → `ProjectDocument+Caches.swift` | SW4a |
| `core/src/edit_time.rs` | 595 | `freeze_frame` with its doc (475–595) → `edit_freeze.rs` | SW7a |
| `app/Sources/AgentCatalog+Clips.swift` | 574 | the edge rows (`trim_start` … `roll`, 247–302) → `AgentCatalog+ClipEdges.swift`, when the file stands at 580 or more | SW7a |
| `core/src/container.rs` | 358 of 400 | the `audio()` builder (:295) → `container_audio.rs`, only if SW5 would pass 400 | SW5 |
| `app/Sources/ContainerRewrapWriter.swift` | 539 | its audio input setup → `ContainerRewrapWriter+Audio.swift`, only if SW5 would pass 600 | SW5 |
| `app/Sources/AudioDynamicsLevels.swift` | 393 of 400 | `// MARK: - The leveller's curves (AU-66 (e))` (257–393) → `AudioDynamicsLevels+Curves.swift`; the class's `private` members the extension reads (`lock`, `curveMemo`, `curveOrder`, `file(media:cache:url:)`) become internal, named in the record | SW3a (SW-35's guard), before SW4b re-keys it |
| `core/src/edit_clip_timing.rs` | 412, over its 400 | `profile_factors` with its doc (42–54) and the `impl Project` helpers `rescale_actions`, `scaled_span`, `scaled_profile` with their docs (57–142) → `edit_speed_profile.rs` in an `impl Project` block, `pub(crate)` | paid by CU9a (412 → 308, its own commit), which needed the helpers first; SW7a owes nothing here (VR7a edits it after) |
| `app/Sources/CanvasSessions.swift` | 1,081, over | `// MARK: - Region drags` (891–1064) → `CanvasRegionDrag.swift`; no member in it is `private` | VR8 |
| `app/Sources/AgentServer+Snapshot.swift` | 377 of 400 | `// MARK: - Main-thread reads` (211–326) → `AgentServer+SnapshotReads.swift`, its `private` funcs internal, only if FC7a's wiring would pass 400 | FC7a |
| `app/Sources/ExportQueueController.swift` | 551 | `// MARK: - Stopping and tidying` (496–551) → `+Stopping.swift`, only if a phase must edit it (none plans to) | first editor |
| `designs/spec/06b-edit-operations-clips.md`, `07.3-frame-recipe.md` | 482, 488 | split by subsection when a phase would take one past ~500 | that phase |

Not edited by any planned phase, so owed by none: `core/src/audio.rs` (581),
`core/src/model_audio.rs` (578), `AudioPane.swift` (554), `InspectorPane.swift` (521),
`CameraCapture.swift` (399), `VideoPane.swift` (871; every new section is a file of its own
registered in `ClipPane.makeSections()`), `MediaImporter+Probe.swift` (381; CU3b adds one call line,
SW3a's readers go in a new file).

**`ReelCore.swift` and its area files (CJ-8 (l)).** The FFI's Swift side is `ReelCore.swift` and
its `ReelCore+<Area>.swift` files (the owner's answer to CJ0a's question 6, 2026-11-01): each of
them may call `rc_*` and no other Swift file does, and a new wrapper goes in the
`ReelCore+<Area>.swift` of its area, as a type of its own or an extension of `ReelProject` (a new
area is a new file, under the 400-line cap for new files). A stored property a wrapper needs on
`ReelProject` (a memo) is added in `ReelCore.swift`. No wrapper is paid for by a doc-only cut any
more. CJ0d's T15 splits the file, one pure move gated alone: `// MARK: - Containers` through
`ReelWebM` (411–612) to `ReelCore+MediaFiles.swift`, `// MARK: - Graphics` (614–739) to
`ReelCore+Graphics.swift`, `takeErrorMessage` and `takeString` losing `private` (766 → about 436
lines); then T15c, gated alone, moves the one call outside the files today,
`rc_agent_string_create` in `AgentServer.swift`'s tool callback (:806), behind a `ReelAgentSocket`
member, the frozen file changing that line only. The wrappers planned and their homes:
`ReelCursor` in `ReelCore+Cursor.swift` (CU1a and CU2, about 30 lines), `ReelProject.cuts()` in
`ReelCore+Cuts.swift` (TX4), the composition plan's options wrapper in `ReelCore+Plan.swift` with
its memo a stored property in `ReelCore.swift` (SW9a, CJ-8 (h)), and `ReelContainer`'s track index
in `ReelCore+MediaFiles.swift` (SW5, wiring).

## Phases

One table, in build order: the phases are listed as they would start if the three lanes ran in step,
CJ0a first. "p" marks a provisional format bump, numbered from 38 in landing order by the integrator
(RC_FORMAT_VERSION is 37). The phase sections below follow this order.

| Phase | Bet | What a person gets | Depends on | Lane | Format |
|---|---|---|---|---|---|
| CJ0a | CJ | Nothing in the app: the scope lifted, the record opened, two spec splits, every spike's rule fixed | — | first, alone | — |
| CJ0b | CJ | Nothing: the core's tolls T1–T4 | CJ0a | A | — |
| CJ0c | CJ | Nothing: the app's tolls T5–T8 | CJ0a | B | — |
| CJ0d | CJ | Nothing: the app's tolls T11–T17 | CJ0a | C | — |
| CJ1 | CJ | Every command that would send to Claude or AssemblyAI greyed without its key, the tooltip naming the key; tools refuse in that sentence | CJ0a | A | — |
| CU0a | CU | Nothing: CU-1…CU-9, the recorder's amendments, tolls U1–U5 | CJ0a | B | — |
| CJ2a | CJ | Agents get `get_media_analysis` with `shots`; the analysis lane, store and reader | CJ0c (T8); CJ-S3, CJ-S4 at its head | C | — |
| TX1 | TX | Agents get `get_timeline_transcript`: the timeline's words, read once per media and kept | CJ0b, CJ0c (T8), CJ0a (T9); TX-S1 at its head | A | — |
| CU0b | CU | Nothing: CU-S1…CU-S4's verdicts | CU0a | B | — |
| CJ2b | CJ | Clip ▸ Split at Shot Changes; the Analyzing sheet | CJ2a, CJ0c (T5) | C | — |
| TX2a | TX | View ▸ Transcript: the fifth inspector tab; read, follow, click to seek | TX1; TX-S2 at its head | A | — |
| CU1a | CU | Nothing: the cursor file's format, the core's read-back, the writer | CU0b, CJ0d (T15) | B | — |
| CO0 | CO | Nothing: CO-1…CO-9; CO-S1, CO-S2 (and CO-S3 if S-KEY1 exists) | CJ0a | C | — |
| TX2b | TX | The tab's bar: Words from, Language, the fill's progress and Stop, the notes | TX2a | A | — |
| CU1b | CU | Every screen recording saves its cursor file beside each movie | CU1a | B | — |
| CO1 | CO | Agents read person masks (`masks`) made on the Mac | CO0, CJ2a | C | — |
| TX3a | TX | Select words and delete them on every unlocked track as one step (TX3 split by size) | TX2a; TX-S3 at its head | A | — |
| TX3b | TX | The pause token: a selectable pause over 1 s, `pauses[]` in `get_timeline_transcript` (TX-34) | TX3a | A | — |
| CU2 | CU | Nothing: the core evaluates a cursor file (mapping, smoothing, idle hide, ripples, path) | CU1a | B | — |
| CO2a1 | CO | Agents set `video.cutout`; the recipe carries a `cutout` key (the plan is unchanged); nothing drawn yet | CO0, CJ0b (T3), CJ0d (T11, T14) | C | p |
| CO2a2 | CO | Remove Background drawn from cached masks in the preview, `render_frame` and every export | CO2a1, CO1, CJ0c (T6) | C | — |
| CP1 | trial | The owner's checkpoint: T1 cut by deleting words; verdict recorded before TX4 | TX3 | A (holds TX4) | — |
| CJ5a | CJ | Nothing: `keep_range`, a timeline range as a whole project (built during CP1) | CJ0b (T1, T4) | A | — |
| CU3a1 | CU | `media.cursor`, `video.cursor` and the recipe's `cursor` key, read back by agents; nothing drawn yet | CU2, CU0a (U5), CJ0b (T2), CJ0d (T11, T14) | B | p |
| CU3a2 | CU | A media whose cursor file has no burned pointer draws its cursor in its clip's layer; exports wait for it | CU3a1 | B | — |
| CO2b | CO | Masks made when a clip asks; exports wait; `render_frame` and Save Frame wait up to 30 s | CO2a | C | — |
| TX4 | TX | Agents list cuts and put back any part of one with `restore_cut` | TX1, CJ0b (T1), CJ0d (T15), CP1 recorded | A | — |
| CU3b | CU | Import and Relink attach a cursor file; Show cursor | CU3a, CU1b | B | — |
| CO3 | CO | The Background section, Clip ▸ Remove Background, `analyze_cutout` | CO2b | C | — |
| TX5 | TX | Cut words greyed in place; Restore Words | TX3, TX4 | A | — |
| CU3c | CU | The recorder stops burning the pointer: Cursor Separate (default) or In the picture | CU3b, CU1b | B | — |
| CO4 | CO | Cleaner edges; Best quality if CO-S1 kept it | CO2a, CO3; CO-S3 | C | — |
| TX6 | TX | The review strikes long pauses and fillers; Clip ▸ Remove Struck | TX3, CJ1 | A | — |
| CU4 | CU | The Cursor section: size, style, smoothing, hide when idle, click ripples | CU3b | B | — |
| CO5 | CO | Insert ▸ Text Behind Subject; the Behind Subject section | CO2b, CO4 | C | p |
| TX7 | TX | Retakes, restarts and repeats struck by comparison; the hand-off to the Assistant | TX6, CJ1; TX-S4 at its head | A | — |
| CU5 | CU | Cursor files travel (Consolidate, the Media tab); `get_cursor_events` | CU3b | B | — |
| CO10 | CO | Remove Background and Behind Subject on stills and pictures | CO4 | C | p |
| TX8 | trial | CJ-5's closing run; no code | TX7 | beside A | — |
| CJ5b | CJ | File ▸ New Project from Range…; the derived document VR and FC open | CJ5a, CJ0c (T5, T7, T8) | A | — |
| CU6 | CU | Record shortcuts, under Input Monitoring | CU1b | B | — |
| CJ3 | CJ | Agents get face samples (`faces`); VR and SW read them | CJ2a; CJ-S2 at its head | C | — |
| FC3 | FC | Agents read laughter, applause and cheering per media (`sound_events`) | CJ2a; FC-S1 | A | — |
| CU7 | CU | Clip ▸ Auto Zoom…; `auto_zoom` | CU5, CU2 | B | — |
| VR1 | VR | View ▸ Show Subjects; the `subjects` kind | CJ2b, CJ3; VR-S1 at its head | C | — |
| FC4 | FC | `find_clips`: sentences, readings and candidate windows for any agent, no key | FC3, TX1, TX7 (the splitter), CJ0c (T8); FC-S3 | A | — |
| CU8 | CU | Clip ▸ Add Shortcut Overlays; `add_shortcut_overlays` | CU5 (CU6 for real data) | B | — |
| VR2a | VR | `reframe_clip` on clips with no actions | VR1; VR-S2 | C | — |
| FC5 | FC | Nothing on screen: the helper's priced estimate, its flags, one helper plumbing | FC-S2 | A | — |
| CU9a | CU | Clip ▸ Retime Range…; `retime_range` | CJ0b (T1) | B | — |
| VR2b | VR | Clip ▸ Follow Subject…; framing composed into existing actions | VR2a, CO2a1 (`edit_action_end.rs`) | C | — |
| FC6 | FC | Nothing on screen: Claude's ranking, checked, priced and cached | FC4, FC5, CJ1 | A | — |
| CU9b | CU | Clip ▸ Speed Up Typing…; `speed_up_typing` | CU9a, CU7, CU8, CU5 | B | — |
| VR3 | VR | File ▸ Make Vertical Version…; `make_vertical_version` | VR2b, CJ5b | C | — |
| FC7a | FC | Clip ▸ Find Clips…: the window, the analysis, the candidates, the wash (no key) | FC4, CJ1, CJ0c (T5) | A | — |
| CU10 | CU | The recorder polishes on landing: zooms, overlays, speed-up | CU3c, CU4, CU6, CU7, CU8, CU9b | B | — |
| VR4 | VR | Captions re-paged, presets by the short side, graphics re-laid | VR3 | C | — |
| FC7b | FC | Rank: the estimate, the ranked list with reasons, its cost | FC6, FC7a | A | — |
| CU11 | CU | Motion blur on zooms and the cursor | CU3a, CU7 (`auto_zoom`); CU-S5 | B | p |
| VR5 | VR | A screen recording's vertical version follows the cursor | VR3 (`VerticalVersion`, `make_vertical_version`), VR2b, CU2, CU5 | C | — |
| FC8a | FC | File ▸ Make Short from Range…; `make_short` | CJ5b, FC4, CJ0c (T5) | A | — |
| CU12 | trial | The owner's screen-tutorial trial with CU's tools | CU10, CU11 | beside B | — |
| CJ6 | CJ | Larger projects, only if CJ-S1 earns it | CJ0a; CJ-S1 at its head | C | — |
| FC8b | FC | Make Shorts from the ranked list | FC7b, FC8a | A | — |
| CO6 | CO | Clip ▸ Camera Layout ▸; `switch_layout` | CO0, CU7 (`action_class.rs`) | B | — |
| SW0 | SW | Nothing: SW-S2's verdict; the dev tool `playback_rebuilds` | CJ0a (question 4 answered yes), CJ0c (T8) | C | — |
| FC9 | FC | Vertical shorts; the owner's Find Clips trial | FC8b, VR3, VR4 | A | — |
| CO7 | CO | The Layout section, the nest offer, the crop centred on the person | CO6, CO1 | B | — |
| VR5b | VR | A screen and its camera in CO's layouts are re-laid, not reframed, in a vertical version (side by side becomes stacked) | VR3, CO6, CO7 (`focus`) | B | — |
| SW1 | SW | Clip ▸ Switch Angle ▸; `copy_pieces` | SW0 (or SW-2's no), CJ0b (T1), CJ0c (T5, T8) | C | — |
| SW3a | SW | Every audio track of a file plays; the Sound tab's Source section | CJ0b (T1, T2, T4), CJ0a (T10), CJ0d (T12, T16), TX7, FC3 (`SoundEvents`); SW-S1 at its head | A | p |
| CO8 | CO | Layout and cutout chosen at record time | CO6, CO3, CU0a (U3, U4), CU10 | B | — |
| SW2a | SW | Nothing visible: the switch's planner and SW-S4's defaults | SW1 | C | — |
| SW3b | SW | Ramps, isolation, voice effects and Reverse read the clip's track | SW3a | A | — |
| CO9 | CO | Hide the camera while silent | CO0, CO2a1 (`edit_action_end.rs`, `cutout_check.rs`) | B | p |
| SW2b | SW | Clip ▸ Switch by Speaker… | SW2a, CJ6 | C | — |
| SW4a | SW | Every track's waveform, loudness, sync and speech caches | SW3b | A | — |
| SW7a | SW | A picture and several sounds linked as one group | CJ0b (T4), CJ0d (T12), TX4, CJ5a, CU9a, SW1 (the road map's own link readers) | B | p |
| SW2c | SW | No hitch at cuts between long-GOP files (only if SW-S2 (a) earns it) | SW0's verdict, SW2b | C | — |
| SW4b | SW | Every measurement and transcript reads the clip's track | SW4a, CO9 (`video_gate.rs`, `hide_silent`), SW2a (`SpeakerSwitch+Read.swift`) | A | p |
| SW8 | SW | Switch by Speaker with one shared microphone, from faces | SW2b, CJ3; SW-S3 | C | — |
| SW5 | SW | An OBS Matroska file brings every audio track | SW3a | A | — |
| VR6 | VR | A two-shot's vertical version follows whoever speaks | VR3 (`make_vertical_version`), VR2b, SW2b, CJ3; VR-S3 | C | — |
| SW6 | SW | A channel as a source | SW4b, SW2b (row H3 runs its S1); SW-S1 | A | p |
| SW9a | SW | View ▸ Angle Viewer; click to switch | SW2b; SW-S2 (c) | C | — |
| SW7b | SW | Detach Audio Tracks and Detach Audio Channels | SW7a, SW3a, SW6 | A | — |
| SW9b | SW | Switching while playing, keys 1–9 | SW9a | C | — |
| VR7a | VR | (asked) A project holds other framings of one cut | CJ0a's question 8 answered yes, VR4, SW7a (`edit_link.rs`, `edit_clip_timing.rs`); VR-S4 at its head | B | p |
| VR7b | VR | (asked) Export any framing | VR7a, SW9a (the plan's options export) | B | — |
| VR8 | VR | (asked) Preview and canvas editing per framing | VR7b | B | — |
| VR9 | VR | (asked) Make Vertical Version writes a linked framing | VR8, VR5b | B | — |

Ten format bumps are planned (CU3a1, CO2a1, CO5, CO10, CU11, SW3a, CO9, SW7a, SW4b, SW6), eleven
with VR7a, since the owner said yes to CJ0a's question 8 (2026-11-01).

**The lanes, in order.**

- **CJ0a** runs alone: it is the record every phase cites. Then **CJ0b, CJ0c and CJ0d run at once**,
  one per lane; their files are disjoint.
- **Lane A, words:** CJ0b → CJ1 → TX1 → TX2a → TX2b → TX3 → **CP1** (lane A builds CJ5a while the
  owner cuts T1; TX4 starts only after CP1's verdict is recorded) → TX4 → TX5 → TX6 → TX7 → CJ5b
  (TX8, the owner's closing run, goes on beside it) → FC3 → FC4 → FC5 → FC6 → FC7a → FC7b → FC8a →
  FC8b → FC9 → SW3a → SW3b → SW4a → SW4b → SW5 → SW6 → SW7b. CJ1 lands before TX because TX6 and TX7
  read `ModelKeys`; FC follows TX because it reads TX1's words and TX7's splitter; the audio-track
  phases come last because they move every per-media reader TX and FC built to a per-source key (SW
  asked for them between TX and FC; the lead order puts FC first — the owner can swap them). Three
  of them wait on other lanes: SW4b on lane B's CO9 (it re-keys `hide_silent`'s source in
  `video_gate.rs` and `model_props.rs`) and lane C's SW2a (it re-keys `SpeakerSwitch+Read.swift`);
  SW6 on lane C's SW2b (its row H3 runs SW2b's S1); SW7b on lane B's SW7a. Lane A meets those waits
  at the end of its run, so it starts SW5 while SW4b waits; if all three are still unlanded, the
  integrator moves the next ready phase of another lane into lane A and records the move.
  SW-35's Switch by Speaker arm is not a wait: whichever of SW3a and SW2a lands second adds it.
- **Lane B, recorder and placement:** CJ0c → CU0a → CU0b → CU1a → CU1b → CU2 → CU3a1 → CU3a2 → CU3b
  → CU3c → CU4 → CU5 → CU6 → CU7 → CU8 → CU9a → CU9b → CU10 → CU11 → CO6 → CO7 → VR5b → CO8 → CO9 →
  SW7a (CU12, the owner's trial, beside it), then VR7a → VR7b → VR8 → VR9 (the owner said yes to
  CJ0a's question 8, 2026-11-01). The camera's layouts follow CU because they touch the recorder panel and the
  landing and reuse CU7's `action_class.rs`; VR5b sits with them because it re-solves their layout
  actions (it waits for lane C's VR3). SW7a waits for its link readers (TX4 and CJ5a in lane A, SW1
  in lane C); linked versions follow it because their carries edit the same `edit_link.rs` and
  `edit_clip_timing.rs`, and VR7b waits for lane C's SW9a.
- **Lane C, pictures:** CJ0d → CJ2a → CJ2b → CO0 → CO1 → CO2a1 → CO2a2 → CO2b → CO3 → CO4 → CO5 →
  CO10 → CJ3 → VR1 → VR2a → VR2b → VR3 → VR4 → VR5 → CJ6 → SW0 → SW1 → SW2a → SW2b → SW2c (if
  earned) → SW8 → VR6 → SW9a → SW9b. The cutout comes early because it is a lead-segment job and the
  analysis lane's first heavy user; CJ6 runs just before SW2b, its only consumer.
- **Serialized merges the integrator watches:** CU3a1/CU3a2 and CO2a1/CO2a2 both edit
  `Compositor.metal`, `LayerUniforms`, `recipe_layer.rs` and `FrameRecipe.swift` within a step of
  each other (texture slots are reserved, CJ-8 (b); `LayerUniforms` groups land in landing order);
  CU's and CO's recorder rows; `op_rows.rs`, `edit.rs`, `scope.rs`, `ReelOps.swift`, the Clip menu,
  `UIMenuTable.swift` and `inventory.json` in every lane; `ClipSnapshot.swift` and
  `TimelineClipDrawing.swift` in SW3a/SW4a (lane A) and SW7a (lane B); SW7a's core files
  (`edit_link.rs`, `edit_time.rs`, `edit_clip_timing.rs`, `edit_edge.rs`, `edit_paste.rs`,
  `edit_nest.rs`, `edit_clip.rs`) against every lane's op that copies or moves clips (TX4's
  `edit_restore.rs`, CJ5a's `keep_range`, CU9a's `retime_range`, SW1's `copy_pieces`, VR7a's
  carries); `AudioDynamicsLevels.swift` in SW3a and SW4b (lane A) after its toll; the frozen
  `TimelineView.swift`, which takes wiring from FC7a (`foundClips`, lane A), CO9 (`gateCurves`, lane
  B) and SW9b (the pending presses, lane C); and the frozen `EditorViewController.swift`'s key
  handlers (TX-S2's option (a), TX's keys, SW9b's bare digits below any modified case of the same
  key).
- **Reordering.** A finding at CP1, TX8 or CU12 may reorder phases; the integrator records it as an
  amendment of CJ-2 before the reordered phase starts.

### CJ0 — scope, the record, the tolls and the spikes

CJ0 is four phases: CJ0a (the record and the spec), then CJ0b, CJ0c and CJ0d (the shared tolls, one
per lane). Every spike's rule is fixed here, at the end of this section.

#### CJ0a — the scope and the record

- **What a person gets:** nothing in the app; the road map opened, its decisions recorded and the
  spec's scope rewritten.
- **First:** ask the owner questions 1–8 below; record the answers.
- **Record:** this file opened (status line, the answers);
  `designs/spec/11-decisions/creator-jobs.md` with CJ-1…CJ-9, VR-1…VR-7, TX-70 and SW-3, and the
  README's rows; the amendment lines in the table below appended to their entries.
- **Spec edits (CJ-1):**
  - `01-what-this-is.md` line 7 "Mac only, Apple Silicon, macOS 26+." becomes "Today it runs on the
    Mac only, Apple Silicon, macOS 26+." Lines 9–40 (the bar sentence and the non-goal paragraph)
    are replaced by: "The bar was a balance: enough to make a real cut with text, shapes,
    transitions and simple animation. Since §11 CJ-1 (2026-11-01) the spec names no non-goal.
    Everything this paragraph once excluded is lifted: multicam (taken up by road map 'creator-jobs'
    as a program track over angle tracks, §11 SW-3); colour grading beyond per-clip controls (GR-1
    onward), with the features once marked not wanted (GR-20, GR-27…GR-30); a plugin system, and
    scripting beyond a graphic's own module (G-1); hosting third-party Audio Unit plug-ins (AU-2);
    motion blur, stabilisation and optical-flow retiming; auto-reframe (taken up as Vision analysis
    plus ordinary actions, §11 VR-1); ML or heavy pixel work outside the compositor's one pass;
    callouts reconstructed after a recording; and any platform but macOS. Screen recording (road map
    3), camera recording (CAM-1) and audio beyond what shipped (AU-2) were lifted before them.
    Lifting makes a thing allowed, not scheduled: what is built is what a road map builds, and the
    guide (`docs/guide/`) says what is built today. Four decisions shape what is built and stand
    until a road map amends them: a graphic is a source (G-1), no third-party Audio Unit is hosted
    (AU-2), effects are closed vocabularies (R5-1), and a recording is ordinary media
    (`recording.md`, as CU-2 amends it)."
  - `02-six-ideas.md` lines 24–26 become: "Left out at day one: everything that only makes sense for
    a recording Frame Job made itself (callouts, pointer effects), templates, publishing to YouTube
    or Vimeo, and a stock-media library. None of these is excluded any longer (§11 CJ-1); graphics
    brought templates (G-44), and road map 'creator-jobs' takes up pointer effects (CU)."
  - `designs/spec/README.md:20`'s row becomes "The product in one page, its opening flow, and the
    scope it no longer limits (§11 CJ-1)"; the Lines cells for 01, 02 and `11-decisions/` are
    updated.
  - The §11 index (`designs/spec/11-decisions/README.md`), where an agent reads first
    (`docs/agents/domain.md`), stops stating the lifted exclusions in the same edit: the file row
    for `recording.md` (:16) gains "(callouts lifted by CJ-1)"; the file row for
    `camera-recording.md` (:44) reads "callouts allowed since CJ-1" for "callouts still out"; the
    `recording.md` decision row (:70) becomes "Screen recording is IN; camera recording IN by CAM-1;
    callouts allowed since CJ-1"; CAM-1's row (:482) "callouts stay OUT" becomes "callouts allowed
    since CJ-1"; AU-2's row (:512) "third-party Audio Unit hosting stays out under the plugin
    non-goal" becomes "no third-party Audio Unit is hosted (the plugin non-goal lifted by CJ-1; the
    decision stands as current design)"; GR-1's row (:326) gains "§1 no longer names grading
    (CJ-1)"; GR-20's and GR-27…GR-30's rows (:345, :352–355) each gain "— not excluded since CJ-1;
    not built". The rows for CJ-1…CJ-9, VR-1…VR-7, TX-70 and SW-3 and the new file's row are added,
    and every Lines cell that moved is updated, so `spec_index_proof.py` still passes.
- **Spec splits (doc-only, every line moved unchanged):** **T9** `07.9a-agent-tools.md` (550) keeps
  the op tools and the gate; the app-state tools move to a new `07.9e-agent-app-state-tools.md`.
  **T10** `04.3b-inspector-clip-sections.md` (520) keeps the video sections; "Audio sections" to its
  end (279–520) move to a new `04.3d-inspector-clip-sections-audio-text-shape.md`, whose index row
  says "continues §4.3b" (renaming 04.3c would move every citation of it). `README.md:11`'s list of
  lettered files and the index rows with their Lines cells change in the same edit.
- **Samples:** `samples/README.md` gains a "Kept outside git" table naming each sample of "Samples
  the owner supplies" and where it lives (question 3).
- **Acceptance:** `make gate` PASS (its `names` and `test` steps read every `*.md`;
  `spec_index_proof.py` checks the index). **Proof rows, mutants, manual checks:** none.
- **Questions for the owner** (asked first):
  **Answered (owner, 2026-11-01):** 1–5, 7, 8 as recommended; 6 as CJ-8 (l) records it, without the Rasterize issue.
  1. Merge into main per phase or at the road map's close? *Recommended: per phase* (fast-forward
     after each landing), since six bets take weeks and other work continues on main.
  2. Lift §2's "Left out" list with §1's? *Recommended: yes* — it is an explicit list of what is
     out.
  3. Where do real samples live, and which will you record when? *Recommended:
     `tools/proof/media/creator/`* (gitignored, as `owner-sync/` is), rows in `samples/README.md`.
     No phase waits for one.
  4. Survey decision 8: one measurement of several 4K angles, a thousand shots and multi-hour files
     (about 34 GB of fixtures, 30–60 minutes of encoding)? *Recommended: yes, as SW's first phase,
     SW0 (SW-S2)*, before any switching code.
  5. "Remove all explicit non-goals" read literally lifts the grading features you marked not wanted
     (GR-20's wide gamut for SDR projects; GR-27…GR-30: an Offset wheel, qualifiers on picture
     clips, 1,024-level scopes, a histogram behind the curves), §1's clause keeping third-party
     Audio Unit hosting out (AU-2) and §1's "nothing else is scriptable" (G-1). Read it that way?
     *Recommended: yes* — nothing on that list is built, and a road map that would build one asks
     you first.
  6. `ReelCore.swift` is over the cap and only its doc blocks are left to cut ("Files at or near the
     cap"); the planned wrappers need more room than they free. When the four blocks are spent, may
     an extension of ReelCore's types in a file named `ReelCore+<Area>.swift` call `rc_*` (the FFI
     contract's "the only file" becoming "`ReelCore.swift` and its `ReelCore+<Area>.swift`
     extensions")? *Recommended: yes, recorded now as CJ-8 (l), so no phase stops mid-pipeline; the
     doc blocks are spent first, in landing order; the root `CLAUDE.md`'s FFI contract is changed in
     the same Frame Job commit, and a `kpgalligan/rasterize` issue (`ai-drafted`, `low-priority`)
     offers Rasterize's parent text the same sentence, as FC5 does for the `agent/` diff.* With a
     no, the phase that finds the room spent stops and asks.
  7. Survey decision 3 was not answered in words. "Add all: 1-6" is read as the six bets as the
     survey wrote them, and bet 1 as written carries decision 3's amendments of TR-3, AI-6 and W-9
     (a review pass may strike repeated phrases by comparing spelled words, TX-70), and bet 2 its
     amendments of `recording.md` (the cursor as data and callouts, CU-1, CU-2). Confirm them?
     *Recommended: yes* — without them bet 1 has no retake pass and bet 2 no cursor file. With a no,
     TX7's retake rows and CU's cursor-file phases are put to you again before they start.
  8. Survey decision 5: a vertical copy only, or linked versions too (one cut holding a framing per
     shape, so a vertical version follows every later edit of the master; a format bump)?
     *Recommended: linked versions too*, built after VR4 and SW7a in lane B (VR7a–VR9, drafted in
     full below), with VR-S4 at VR7a's head. The copy (VR3) ships first either way. The vertical
     trial (VR-38) may still withdraw the yes before VR7a starts if it finds copies cost nothing to
     re-make; with a no, VR7a–VR9 are filed as one issue carrying their design.

**CJ0a's decisions (draft text).**

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

**Scope-level decisions of the bets, recorded at CJ0a (their phases' sections hold the rest).**

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

**Amendment lines appended at CJ0a.**

| Entry | Line appended |
|---|---|
| `recording.md`, first bullet | "**Amended by CJ-1** (2026-11-01): callouts, and reconstructing afterwards what the recorder saw, are no longer out; they are allowed, not scheduled, and CU's phases record what they build. 'A recording is ordinary media' (the next bullet) stands until CU-2. **Amended by CJ-4**: the recorder panel may ask for Input Monitoring, opt-in." |
| CAM-1 | "**Amended by CJ-1** (2026-11-01): 'callouts stay OUT' no longer holds; callouts are allowed, not scheduled." |
| AU-2 | "**Amended by CJ-1** (2026-11-01): §1's clause keeping third-party Audio Unit hosting out is lifted. The decision stands as current design: none is hosted, and a road map that would host one amends this entry first." |
| G-1 | "**Amended by CJ-1** (2026-11-01): §1's clause 'nothing else is scriptable' is lifted with the plugin non-goal. A graphic stays a source and nothing else becomes scriptable until a road map decides it in writing." |
| R5-1 | "**Noted by CJ-1** (2026-11-01): the plugin non-goal is lifted; effects stay closed vocabularies until a road map amends this entry." |
| GR-1 | "**Noted by CJ-1** (2026-11-01): §1 no longer lists grading as a non-goal." |
| GR-20, GR-27, GR-28, GR-29, GR-30 | "**Amended by CJ-1** (2026-11-01): no longer excluded by §1; not built. This was the owner's verdict, so a road map that would build it asks the owner first." |

Later amendments are recorded by the phase that makes them, before its code, and listed in its
section (CJ1's R6-17, AI-8 and TR-10; TX's TR-14, TR-11, AI-4, AI-14; CU's `recording.md`, CAM-4,
CAM-9; and so on).

#### CJ0a's record (2026-11-01)

**Landed.** One documents-only commit on `worktree-creator-jobs`, base `d0661e5d`; no file under
`app/`, `core/`, `graphic/`, `mcp-proxy/`, `agent/` or `tools/` changed.

- **The road map and the brief:** this file and `designs/creator-survey.md` added. This file's head
  says it is opened; the answered conditionals read as the answers ("The orchestrator's defaults",
  the format-bump count, lane B's order, VR7a's gate, CJ0a's questions and "Questions asked at
  phase time"); the draft entries CJ-1, CJ-2, CJ-6, CJ-7, CJ-8 (l), VR-3 and TX-70 carry the same
  changes as the §11 file, so the two read alike. CJ-7's `rule_sha256` is now over the entry's first
  line and every following line that begins with two spaces, and CJ-7 and CJ-2 name the road map,
  not "this file", as where spike rules, phase records and "Phases" live (the review's finding).
- **The decisions:** `designs/spec/11-decisions/creator-jobs.md` (216 lines) holds CJ-1…CJ-9,
  VR-1…VR-7, TX-70 and SW-3, each with its row in `11-decisions/README.md` (18 rows) and the file's
  row after `audio.md`'s.
- **The amendment lines** of the table above, appended to their entries: `recording.md`'s first
  bullet, CAM-1 (`camera-recording.md`), AU-2 (`audio.md`), G-1 (`graphics.md`), R5-1
  (`effects-motion.md`), GR-1 (`grading.md`), GR-20 (`grading-3.md`), GR-27…GR-30
  (`grading-4.md`); and TX-70's three, on TR-3 (`cut-by-transcript.md`), AI-6 (`assistant.md`) and
  W-9 (`word-captions.md`).
- **The §11 index** stops stating the lifted exclusions: the rows "Spec edits" names (the file rows
  for `recording.md` and `camera-recording.md`, the `recording.md` decision row, GR-1, GR-20,
  GR-27…GR-30, CAM-1, AU-2), and three file rows beyond that bullet, because they too stated a
  lifted exclusion as in force: `grading-3.md` (GR-20's clause gains "— not excluded since CJ-1;
  not built"), `grading-4.md` (GR-27's, GR-28's, GR-29's and GR-30's clauses, the same) and
  `audio.md` ("third-party plug-in hosting stays out" became "no third-party Audio Unit is hosted
  (the plugin non-goal lifted by CJ-1; the decision stands as current design)"). G-1's row gains
  "— amended by CJ-1", TR-3's "— amended by TX-70", AI-6's and W-9's name TX-70 beside their
  earlier amenders. Every Lines cell that moved was set from `wc -l`.
- **Spec §1 and §2 (CJ-1):** `01-what-this-is.md` 47 → 34 lines (line 7 and the bar and non-goal
  paragraph, as "Spec edits" gives them); `02-six-ideas.md` 26 → 28 (the "Left out" paragraph).
- **The splits, every moved line byte-identical:** T9 `07.9a-agent-tools.md` 550 → 97, the
  app-state tools (old 87–539) to the new `07.9e-agent-app-state-tools.md` (457, under a four-line
  head); old line 86's closing "Plus" became a pointer to §7.9e, which also names the op tools
  `set_media_color`, `set_media_speech` and `set_audio`'s `duck.mode` whose text moved with the
  app-state tools. T10 `04.3b-inspector-clip-sections.md` 520 → 277, "Audio sections" to the end
  (old 279–520) to the new `04.3d-inspector-clip-sections-audio-text-shape.md` (246). The
  cross-reference lines of §7.9a–§7.9d, §4.3a, §4.3b and §4.3c, `spec/README.md`'s rows, its line 11
  and its Lines cells changed with them.
- **Answer 6 (CJ-8 (l)):** the rule that one Swift file calls `rc_*` became `ReelCore.swift` and
  its `ReelCore+<Area>.swift` files in the root `CLAUDE.md` (the FFI contract and the recipe's step 2),
  `app/CLAUDE.md`'s `ReelCore.swift` entry, spec §7.1, §7.4 and §8, and `docs/developing.md`;
  `designs/adr/app-file-history.md`'s "Core edge" toll is marked superseded, and its
  `ReelCore.swift` entry names T15's split as the next seam. In this file the room ledger became
  "`ReelCore.swift` and its area files", and the tolls row, CJ0d's T15 (with T15c), CU-9, CU1a, TX4,
  SW5, SW9a, "Closing the road map" and "Risks" follow it. CU-9's title, "their wrapper pays for its
  room", became "their wrapper is a ReelCore file of its own", since no room is paid.
- **Samples (answer 3):** `samples/README.md` gains "Kept outside git", one row per sample of
  "Samples the owner supplies", each under `tools/proof/media/creator/<ID>/`, none recorded yet.

**The owner's answers (2026-11-01, verbatim):**

> 6. ReelCore.swift should be extended to multiple files
>
> Accept all other recommendations. Start and use /litecode

Recorded as: 1 each landing merged into main by fast-forward (CJ-6); 2 §2's "Left out" lifted with
§1's non-goals (CJ-1); 3 samples in `tools/proof/media/creator/` with rows in `samples/README.md`; 4
SW-S2 run in SW0; 5 the literal reading, nothing on its list built (CJ-1); 6 `ReelCore.swift` and
its `ReelCore+<Area>.swift` files may call `rc_*`, each new wrapper in the file of its area,
`ReelCore.swift` split at CJ0d's T15 (CJ-8 (l)), without the Rasterize issue; 7 TX-70's amendments
of TR-3, AI-6 and W-9 and CU's of `recording.md` (TX-70, CU-1, CU-2); 8 linked versions as well as
the copy, VR7a–VR9 after VR4 and SW7a with VR-S4 first (VR-3).

**Spike rules fixed.** "Every spike, with its rule" is not edited by CJ0a. Each entry's SHA-256
under CJ-7's definition (the entry's first line and every following line that begins with two
spaces, each with its newline), computed after CJ0a's last edit; a spike's `results.json` stores
its value as `rule_sha256`, and a run whose rule hashes differently re-records it here first.

| Spike | `rule_sha256` |
|---|---|
| CJ-S1 | `e4ead1af47d079314698d3cf13ee84dfe9d35cace69182bf2fc63c772d12e2f5` |
| CJ-S2 | `c41417fb1f72f98f72225c7fb8b0ffd22b04150c8bed4c2836dd75d395bb2b11` |
| CJ-S3 | `209c6f01726c2c969e87c3146019a75f69ea86cec8ccac646f3e67f0309ce830` |
| CJ-S4 | `eea6c19036b19e7cc5bb0ed0c8d49f649d3b7653beda35937a8d8a77ab46f9d1` |
| TX-S1 | `5f784283c6a525aa8029942d0cf5aa91ac2b65d548576861d12ff1d25b2c043b` |
| TX-S2 | `543a30274c8dc99a2404daee513faeefc6248c912cc078036d74c24dad40c09a` |
| TX-S3 | `bede33d2161aefe5fdf2d942c9d6869874937f41cb39066cc16ebd89bbf3c5a0` |
| TX-S4 | `943b1d979214bfae87c072982a44afb67a9cdc2687009f32bc04878f28f62cc7` |
| CU-S1 | `9508e82d119466262ed5fa48b7b3a6502b12022fa65b63ac0a35badfee23886c` |
| CU-S2 | `15d61ec5374d3465b7f8a2f7c652ed6d78b099d0c2c5642946d8c87b3919c851` |
| CU-S3 | `9ffadf0b9897880826cdddc0820ddc93bb0a2337bdf27e73b51c6fa41372ea5c` |
| CU-S4 | `0fe71118ada7d67c52790943eb6cd5cf0c8b160377df3a72df207d54db47e208` |
| CU-S5 | `7e6b75fb54d4241053ad09724bff904b1cacaead75dc25b2072801436033b826` |
| CO-S1 | `035665d178e29749cf6ae5d14e12bb462768b969d84b39bbbd7290f49c9fd05a` |
| CO-S2 | `577a8f392efc3bd086165af2e1f9be01ca480f08cf6c54deca498bad30709eee` |
| CO-S3 | `84ae691664c9d8293b50f70e1f332e68a032984da4f2ae65500561f152e9319f` |
| VR-S1 | `6650e95dbe2d3516fb73cb9ac0c892f60178b9d1e4e7ced7ed63e133f03c28ac` |
| VR-S2 | `f55e33e6553ee691a366ee07d535a57ba90d61ae9a1a588a7ea2b13cce3870e7` |
| VR-S3 | `b6fe6f5a6f565941f6cabd27f2a7f7d5b28a8644cbb433cbe6cf5ceeaf0b6054` |
| VR-S4 | `f9ae2e4770a5c05aba2f6e833e334c3d6fcc0f775d1c7511b0fef3aba2865fcd` |
| FC-S1 | `7fe7bcabb781cb3c54e3939a789b80ad410a13d595fc093369088d7fa8b06989` |
| FC-S2 | `69f97c55cce082e4c18ae00e7ccc9f64ad0dcdffe799e03af31fc40757c1b2b7` |
| FC-S3 | `41671b81fca4e9ba1008405f72b66536163385903a1bbb06e75d9f47a6a3e331` |
| SW-S1 | `4d601156b5b831f19fcdf243f5643870cb3faa68f03e8d744fde08d73446ba43` |
| SW-S2 | `ecd9d732bf8ec0c13b417c768577092f1b175728ac425c319529ba19324f0961` |
| SW-S3 | `abc5ccefef8614fdb571da20c44f0768ad2e40bd4066ba7b90870359fd3f1fae` |
| SW-S4 | `3d8c9c46221e111f713c46d8618a95417ea945707933e6a01fb671eca3fcdb3a` |

**Verification.** `make gate`.

**To file** (one optional candidate, not filed: the owner's answer 6 did not ask for it): a
`kpgalligan/rasterize` issue (`ai-drafted`, `low-priority`), "Let the FFI's Swift side be
RasterCore.swift and its RasterCore+<Area>.swift files", offering Rasterize's parent text CJ-8
(l)'s sentence: "The FFI's Swift side is the core file and its `+<Area>.swift` files; each of them
may call the core's exports and no other Swift file does; a new wrapper goes in the file of its
area."

#### CJ0b — the core's tolls T1–T4

- **What a person gets:** nothing. Room in four core files, each a pure move landed and gated alone
  and diffed line-identical against the base (AP0's precedent).
- **T1** `core/src/op_table.rs` (374 of its 400): `OP_TABLE` (246–362) with `OP_NAMES` and `names()`
  (363–374) out whole to `op_rows.rs`, re-exported by `op_table.rs`; `req`, `opt`, `within` and `op`
  become `pub(crate)`. Every bet that adds an op adds rows there.
- **T2** `core/src/model.rs` (570): the media types (`// ---- media`, 156–217: `Media`,
  `MediaOriginal`, `MediaKind`) out whole to `model_media.rs`, re-exported. CU and SW add media
  fields.
- **T3** `core/src/recipe.rs` (547): the content hash (`FNV_OFFSET`, `FNV_PRIME`, `fnv1a`,
  `content_hash`, `sorted`, 80–119) out to `recipe_hash.rs`. CU and CO add layer keys.
- **T4** `core/src/edit_clip.rs` (616, over): `TITLE_FONT` and `TITLE_CONTENT` (67–72), `Described`
  (78–84) and `add_text_clip`, `add_shape_clip`, `add_described_clip` with their docs (227–366;
  367–387 are the `// ---- moving` banner and `move_clips`' doc and stay) to `edit_described.rs` in
  a new `impl Project` block. `DEFAULT_CLIP_DURATION` (62) stays (read by
  `whole_media_length`, :156) and becomes `pub(crate)`; `edit_adjustment.rs:63` and
  `edit_graphic.rs:34` change their `use` lines; `lib.rs` gains the module. SW3a later reaches
  every exhaustive `Source::Media { media, r#in, reversed }` pattern or literal in `core/src`
  (twelve at `d0661e5d`, none with `..`): `edit_clip.rs:203, :589, :602` (the move leaves them
  where they are), `edit_background.rs:300`, and the pattern-then-literal pairs that rebuild a
  source from its parts in `edit_edge.rs:92/96` (slip), `edit_paste.rs:118/122` and
  `source_window.rs:180/184, :217/221`.
- **Map entries:** `core/CLAUDE.md` (`op_rows.rs`, `model_media.rs`, `recipe_hash.rs`,
  `edit_described.rs`); spec §7.10; each file's "Named next cuts" in `core-file-history.md`.
- **Acceptance:** `make gate` PASS after each toll; each move diffed line-identical; `cargo fmt`
  leaves the moved text as it was. **Proof rows, mutants, manual checks, questions:** none.

#### CJ0b's record (2026-11-01)

**Landed.** Four pure moves in `core/src`, one commit each on lane A's branch, base `ba535d61`;
no FFI, header, op, format or Swift change, and `RC_FORMAT_VERSION` is unchanged. Every count
below is a `wc -l` run.

| Toll | Commit | Old file, before → after | New file | Widened |
|---|---|---|---|---|
| T1 | `72275320` | `op_table.rs` 374 → 238 | `op_rows.rs` 148 | `req`, `opt`, `within`, `op` → `pub(crate)` |
| T2 | `6001a1fc` | `model.rs` 570 → 512 | `model_media.rs` 71 | nothing |
| T3 | `ca57875c` | `recipe.rs` 547 → 508 | `recipe_hash.rs` 45 | nothing |
| T4 | `4849d874` | `edit_clip.rs` 616 → 444 | `edit_described.rs` 181 | `DEFAULT_CLIP_DURATION` → `pub(crate)` |

- **T1:** `OP_TABLE` (its doc and `#[rustfmt::skip]`), `OP_NAMES` and `names()` to `op_rows.rs`,
  with the two `use` lines only the rows name; `op_table.rs` re-exports both (`pub use
  crate::op_rows::{OP_NAMES, OP_TABLE}`). `edit_canvas.rs:30`'s doc names `op_rows.rs`'s table.
- **T2:** the `// ---- media` banner, `Media`, `MediaOriginal`, `MediaKind` to `model_media.rs`;
  `model.rs` re-exports the three after `Track`'s re-export.
- **T3:** `FNV_OFFSET`, `FNV_PRIME`, `fnv1a`, `content_hash`, `sorted` to `recipe_hash.rs`;
  `recipe.rs` re-exports `content_hash` `pub(crate)`. The doc lines in `recipe_text.rs` (the
  "What is NOT here" paragraph) and `core/tests/evaluate_tests.rs` (the FNV oracle's doc) name
  `recipe_hash.rs`.
- **T4:** `TITLE_FONT`, `TITLE_CONTENT`, `Described`, and `add_text_clip`, `add_shape_clip`,
  `add_described_clip` (in a new `impl Project`) to `edit_described.rs`, whose module doc carries
  `edit_clip.rs`'s paragraph on the two ops that take a patch; `edit_clip.rs`'s module doc names
  the new home in one line, and its imports lost the nine items only the moved code named.
  `edit_adjustment.rs` and `edit_graphic.rs` `use crate::edit_described::Described`. Doc lines
  naming the new home: `edit_graphic.rs:8`, `props_check.rs:13` and `:29`, `recipe_text.rs`'s
  `TITLE_FONT` reason. The `Source::Media` patterns in `add_clip` and `set_reversed` stay in
  `edit_clip.rs`.
- **Line identity.** For each moved range, `git show ba535d61:core/src/<old>.rs | sed -n
  '<a>,<b>p'` against `sed -n '<x>,<y>p' core/src/<new>.rs`, after `cargo fmt`; each `diff` printed
  nothing (exit 0): T1 `op_table.rs` 238–374 = `op_rows.rs` 12–148 (137 lines); T2 `model.rs`
  156–216 = `model_media.rs` 11–71 (61); T3 `recipe.rs` 80–118 = `recipe_hash.rs` 7–45 (39); T4
  `edit_clip.rs` 39–42 = `edit_described.rs` 4–7 (4), 64–72 = 20–28 (9), 76–84 = 30–38 (9),
  227–366 = 41–180 (140). `git diff ba535d61 -- core/src/{op_table,model,recipe,edit_clip}.rs`
  adds only the four builders' `pub(crate)`, the three re-exports (two with their `///` doc),
  `edit_clip.rs`'s pruned `model` import, its one `//!` line and `DEFAULT_CLIP_DURATION`'s
  `pub(crate)`; every other line is a deletion.
- **Per-toll gate** (each toll, before its commit, from `core/`): `cargo fmt` (no moved line
  changed), `cargo fmt --check` exit 0, `cargo test --release` exit 0 (171 result lines, 1806
  passed, 0 failed, at each of the four), `make lint` exit 0 with no warning line, and
  `python3 tools/proof/spec_index_proof.py` (222/222 checks passed) after each 07.10 row.
- **`make gate`** once after T4, at `4849d874`: PASS 356 s. `build/gate/times.tsv`: names pass
  0.7 s, typecheck skip (inputs byte-identical to its last pass; no Swift changed), fmt pass 3.1 s,
  lint pass 1.0 s, test pass 173.9 s (198 result lines, 1976 passed, 0 failed), app pass 176.5 s
  (D25 and D26 ok).
- **Documents:** spec §7.10 gained the four rows after their parents' and rewrote the
  `op_table.rs`, `edit_graphic.rs`, `edit_adjustment.rs` and `recipe.rs` rows (128 → 132 lines,
  `spec/README.md`'s cell set from `wc -l`); `core-file-history.md`'s "Named next cuts" gained an
  `op_table.rs` bullet and extended `model.rs`'s, `recipe.rs`'s and `edit_clip.rs`'s. The
  `core/CLAUDE.md` map entries are owed to the integrator (lanes edit no `CLAUDE.md`).

**On `worktree-creator-jobs`.** Cherry-picked after CJ0c's record without conflict: `70993ac5`
(T1), `52e83fb5` (T2), `97cf2158` (T3), `23debe6e` (T4), `ccb0bc21` (this record's first
part), each toll still its own commit.

**Deviations.** `props_check.rs:13` ("a new title or shape") also named `edit_clip.rs` and now
names `edit_described.rs`, under the rule that a doc sentence a move makes false is fixed;
`recipe_text.rs`'s T3 rewrite took three lines; `edit_described.rs`'s opening sentence takes two
`//!` lines (100 columns); the acceptance line above asks for `make gate` after each toll, and
per this phase's spec each toll was held to fmt, test and lint, with `make gate` once after T4.

**Review.** Verdict pass, two nits, both doc sentences T3 made false and the spec's list missed:
`recipe.rs`'s module doc still said the `content_hash` stays there, and `recipe_text.rs`'s "What
is NOT here" paragraph kept a short unreflowed line and a "stays there too" that, after two files
are named, no longer said which. Fixed at integration: `recipe.rs` says the hash is
`recipe_hash.rs`'s, re-exported, and the paragraph is reflowed with "stays in `recipe.rs` too"
(`recipe_text.rs` 551 → 550).

**Map entries, at integration.** `core/CLAUDE.md`: `model_media.rs`, `edit_described.rs` and
`recipe_hash.rs` entries, the `op_table.rs` entry naming `op_rows.rs` and the `pub(crate)`
builders, `model.rs`'s naming `model_media.rs`, `edit_graphic.rs`'s and `edit_clip.rs`'s naming
`edit_described.rs`; `edit_clip.rs` (444) is no longer over the cap, so its "known debt" clause
and its name in the Rules paragraph's over-the-cap sentence went, leaving `edit.rs` alone there.
`make gate` after the picks, the two fixes and these edits: names pass, typecheck skip (no Swift
or header changed), fmt, lint, test (198 result lines, 1976 passed, 0 failed) and app (D25, D26
ok) each pass, "gate: PASS 232s".

**Owed.** Nothing: no proof rows, mutants or manual checks, and nothing to file.

#### CJ0c — the app's tolls T5–T8: menus, builder, document, dispatch

- **What a person gets:** nothing.
- **T5** `AppDelegate+Menus.swift` (554): the View menu whole (`viewMenu`, `trackHeightMenu`,
  `previewQualityMenu`, 442–526; 528–535 are `windowMenu()`'s doc and stay) out to
  `AppDelegate+ViewMenu.swift`. `viewMenu` loses `private`
  (`:54` calls it); the other two stay `private` beside it. Any `inventory.json` site the move
  carries is re-pinned (`inventory.py --check` names it).
- **T6** `CompositionBuilder.swift` (546): `// MARK: - The held last frame` (428–519) out to
  `CompositionBuilder+HeldFrame.swift`, carrying the `timeRange` deprecation (:457–458); the
  `TYPECHECK_BASELINE` row in `tools/proof/gate.py` (:87–88) names the new file, and root
  `CLAUDE.md`'s "2 in `CompositionBuilder.swift`" becomes "1 in `CompositionBuilder.swift`, 1 in
  `CompositionBuilder+HeldFrame.swift`".
- **T7** `ProjectDocument.swift` (1,336, over): `// MARK: - Reverse (spec §11)` (827–980, methods
  only) out whole to `ProjectDocument+Reverse.swift`, dropping `private` on the three stored
  properties it uses (:364–369, used at :900, :921, :942, :955, :970), re-pinning any
  `inventory.json` or proof anchor on a moved line.
- **T8** `AgentServer.swift` (807, frozen): a new `AgentServer+CreatorJobs.swift` holding an empty
  `creatorHandlers` table, an empty `creatorOffMainTools` set and `withCreatorHandlers`, the twin of
  `withDevHandlers` (`AgentServer+DevTools.swift:41–53`): a road-map tool reusing a product tool's
  name keeps the product handler, traps on Debug and logs a "Frame Job: " line on Release. The
  frozen file changes two existing lines: :115 becomes
  `productOffMainTools.union(creatorOffMainTools).union(devOffMainTools)`, :335 becomes
  `withDevHandlers(withCreatorHandlers(productHandlers))`; its doc sentence about where a new non-op
  tool belongs points at the new file.
- **Map entries:** `app/CLAUDE.md` (the four files); spec §7.4; `app-file-history.md`'s "Named next
  cuts".
- **Acceptance:** `make gate` PASS after each toll, at exactly the four baseline warnings; each move
  diffed line-identical. **Proof rows, mutants, manual checks, questions:** none.

#### CJ0c's record (2026-11-01)

**Landed.** Six commits on lane B's own branch, base `ba535d61` (`app/Sources` and `tools/`
unchanged there from `d0661e5d`, so the ranges above held when re-read): one per toll, each a pure
move typechecked alone, then this record's documents commit and the review's fix. On
`worktree-creator-jobs` they are `1c73b6e0` (T5), `5b64debe` (T6), `59c77fe3` (T7), `a6c54e44`
(T8), `14aed878` (documents) and `d085a0ad` (the fix), cherry-picked without conflict. Nothing a
person or an agent can see changed.

- **T5:** `viewMenu`, `trackHeightMenu` and `previewQualityMenu` (442–526) to
  `AppDelegate+ViewMenu.swift`; `viewMenu` internal. `wc -l`: `AppDelegate+Menus.swift` 554 → 471,
  `AppDelegate+ViewMenu.swift` 100. No `inventory.json` site moved (`inventory.py --check` 5/5).
- **T6:** `// MARK: - The held last frame` through `missingClips` (428–518) to
  `CompositionBuilder+HeldFrame.swift`; `heldTail` and `missingClips` internal. `wc -l`:
  `CompositionBuilder.swift` 546 → 454, `CompositionBuilder+HeldFrame.swift` 108. The `timeRange`
  warning reports at `CompositionBuilder+HeldFrame.swift:47`, and `TYPECHECK_BASELINE`'s row names
  that file (`gate.py --selftest` 35/35).
- **T7:** `// MARK: - Reverse (spec §11)` through `reverseRenderDidFinish` (827–979) to
  `ProjectDocument+Reverse.swift`; `private` dropped on the three stored properties (:364, :368,
  :369). `wc -l`: `ProjectDocument.swift` 1336 → 1182, `ProjectDocument+Reverse.swift` 169.
  `inventory.json`'s site became `ProjectDocument+Reverse.swift:122` (`host.presentAsSheet(`), and
  its five `gate` anchors and the `retryReversedMedia` anchor moved with it; the `via` anchors stay
  on `ProjectDocument.swift` (`inventory.py --check` 5/5).
- **T8:** `AgentServer+CreatorJobs.swift` (43 lines: `withCreatorHandlers`, an empty
  `creatorHandlers`, an empty `creatorOffMainTools`); `AgentServer.swift` 807 → 808 by its :115 and
  :335 lines and its tool-table doc sentence.
- **The moves' diffs:** each moved range diffed against `ba535d61`'s lines: T5 differs only on
  `viewMenu`'s line, T6 only on `heldTail`'s and `missingClips`' lines, T7 not at all. The base
  files' own diffs are removals, the three `private` drops, `+Menus`' head doc and
  `AgentServer.swift`'s three edits.
- **Documents:** `app-file-history.md`'s three "Named next cuts" entries and its frozen-files
  bullet; spec §7.4's rows for `ProjectDocument.swift`, `CompositionBuilder.swift`, the
  `AppDelegate` row and the `AgentServer` row (80 lines still, `spec_index_proof.py` 222/222).

**Deviations.**
- `heldTail` and `missingClips` lost `private`, which T6 above does not name: Swift's `private`
  reaches only its own file, and their callers (`fill`, `build`) stay in `CompositionBuilder.swift`.
- `AppDelegate+Menus.swift`'s head doc was amended so it stays true: the menus it builds and the
  toll paragraph name `AppDelegate+ViewMenu.swift` and `viewMenu()`. Its count was already one high
  (it said ten menus here and Insert the eleventh, where `buildMainMenu()` hangs ten in all); it
  now says eight here, Insert the ninth and View the tenth.
- `AgentServer.swift`'s doc sentence grew from two lines to three.
- The acceptance line above asks for `make gate` after each toll; per this phase's spec each toll
  was held to `make typecheck` (and `inventory.py --check` or `gate.py --selftest` where it
  touched them) alone, and `make gate` ran once at the end.

**Verification.** `make typecheck` after each toll: 0 errors, exactly the four baseline warnings,
tsc silent. `make gate`: names, typecheck, fmt, lint, test and app each `pass`, "gate: PASS 483s" (exactly
the four baseline warnings, the `timeRange` one in `CompositionBuilder+HeldFrame.swift`; BUILD
SUCCEEDED through the Write Agent Catalog step's parity check over the merged handlers).

**Review.** The first review re-ran the three moved-line diffs (as above) and found one blocker:
the record's insertion had replaced the `#### CJ0d` heading, leaving CJ0d's body under this record.
`d085a0ad` restored the heading, so this file's diff against `ba535d61` is a pure insertion of the
record; the second review re-ran the diffs and passed with no findings.

**Map entries, at integration.** Root `CLAUDE.md`'s typecheck-baseline sentence names one warning
in `CompositionBuilder.swift` and one in `CompositionBuilder+HeldFrame.swift`; `app/CLAUDE.md`
gains `+ViewMenu` in the `AppDelegate.swift` entry, `+HeldFrame` in `CompositionBuilder.swift`'s,
`+Reverse` in `ProjectDocument.swift`'s, and an `AgentServer+CreatorJobs.swift` bullet before
`AgentServer+DevTools.swift`'s (the frozen `AgentServer.swift` entry unchanged). `make gate` on
`worktree-creator-jobs` after the picks and these edits: names, typecheck, fmt, lint, test and app
each `pass`, "gate: PASS 361s", the four baseline warnings as above.

**Owed.** Nothing: no proof rows, mutants or manual checks, and nothing to file.

#### CJ0d — the app's tolls T11–T17: snapshots, recipe, core edge, importer, reverse

- **What a person gets:** nothing.
- **T11–T13** `ProjectSnapshot.swift` (1,454, over), its named shape "a property group's snapshot
  types out, whole": `VideoProps` with its doc (784–895) → `VideoProps.swift`; `// MARK: - Clips`
  (896–1173: `ClipSource` with its `private enum CodingKeys`, `ClipSnapshot`, `TransitionSnapshot`)
  → `ClipSnapshot.swift`; `// MARK: - Tracks` (`TrackSnapshot`, 443–505) → `TrackSnapshot.swift`.
  The file goes to about 1,003; nothing else in those ranges is `private`.
- **T14** `FrameRecipe.swift` (417, over its 400): `RecipeLayerMatte` with its doc,
  `RecipeLayerDissolve`, `RecipeMatteGroup` (213–270; `RecipeLayer`'s doc at 272–273 stays with
  it) → `FrameRecipe+Mattes.swift`.
- **T15** `ReelCore.swift` (766, over), split into its area files (CJ-8 (l)), one pure move gated
  alone: the media-file wrappers (`// MARK: - Containers` through `ReelWebM`, 411–612) →
  `ReelCore+MediaFiles.swift`, the graphics wrappers (`// MARK: - Graphics`, 614–739) →
  `ReelCore+Graphics.swift`, `takeErrorMessage` and `takeString` losing `private` (766 → about 436
  lines). In the same toll the file header's first sentence and its list of types, and
  `core/include/framejob_core.h:5`'s lockstep comment, name the ReelCore files. **T15c**, gated
  alone after it: the one `rc_*` call outside the ReelCore files, `rc_agent_string_create` in
  `AgentServer.swift`'s tool callback (:806), moves behind a `ReelAgentSocket` member; the frozen
  file changes that line only.
- **T16** `MediaImporter.swift` (589): the named seam, the frames loop's per-result write, cannot
  move whole. The `switch result` body (388–405) holds `guard pass?.isCurrent() ?? true else {
  break frames }` (:393), a labelled break to the `frames:` loop at :386 that cannot cross into a
  function in another file, and it writes the loop's locals (`written`, `tiles`) and reads `pass`,
  `directory`, `lastTime` and `held`. So T16 is a small refactor gated alone, not a pure move: the
  `.success` arm's tile loop (389–398) becomes `writeTiles(_:requested:lastTime:held:directory:
  pass:into:) -> Int?` in `MediaImporter+Thumbnails.swift` (await-free: `nil` once the pass is
  superseded, else the tiles written, each written index inserted into `written` through `inout`),
  and the arm becomes `guard let count = writeTiles(…) else { break frames }; tiles = count`, so the
  labelled break stays in the loop; about seven lines freed. `cache_pass_probe.py`'s
  `frame-check-ignored` mutant, whose anchor is the moved guard, is re-aimed at the helper's guard
  in `MediaImporter+Thumbnails.swift` and run with row S1b; the history entry records the re-aim and
  that this toll is not line-identical.
- **T17** `ReverseRenderer.swift` (574): `// MARK: - Settings` (480–574: `dimensions`,
  `videoSettings`, `sliceDuration`) → `ReverseRenderer+Settings.swift`.
- **Map entries:** `app/CLAUDE.md`'s snapshot list (`VideoProps.swift`, `ClipSnapshot.swift`,
  `TrackSnapshot.swift`), `FrameRecipe+Mattes.swift`, `MediaImporter+Thumbnails.swift`,
  `ReverseRenderer+Settings.swift`, `ReelCore+MediaFiles.swift`, `ReelCore+Graphics.swift`; spec
  §7.4; "Named next cuts"; `app-file-history.md`'s `ReelCore.swift` entry records T15's and T15c's
  before and after counts.
- **Acceptance:** `make gate` PASS after each toll; each move diffed line-identical but T16, which
  instead passes `cache_pass_probe.py` whole with its re-aimed mutant killed (S1b). **Proof rows,
  mutants, manual checks, questions:** none beyond T16's.

#### CJ0d's record (2026-11-01)

**Landed.** Lane C, eight toll commits and one documents commit on the lane's branch
(`worktree-wf_14ad530d-40f-15`), base `ba535d61`, each picked onto `worktree-creator-jobs` as
its own commit (below). Nothing a person sees changed. Every range was re-read at the base (identical to `d0661e5d`'s
but for the road map's off-by-one ends: T11 is 784–894, T12 896–1172, T13 443–504, each with
the blank line after it).

| Toll | Lane commit | What | `wc -l` before → after | New file |
|---|---|---|---|---|
| T12 | `9dcb74f9` | `// MARK: - Clips` (`ClipSource` with its nested `CodingKeys`, `ClipSnapshot`, `TransitionSnapshot`) | `ProjectSnapshot.swift` 1454 → 1176 | `ClipSnapshot.swift` 283 |
| T11 | `26509ab8` | `VideoProps` with its doc | 1176 → 1064 | `VideoProps.swift` 116 |
| T13 | `c6b45ce2` | `// MARK: - Tracks`, `TrackSnapshot` | 1064 → 1001 | `TrackSnapshot.swift` 67 |
| T14 | `e4e97765` | `RecipeLayerMatte`, `RecipeLayerDissolve`, `RecipeMatteGroup` | `FrameRecipe.swift` 417 → 358 | `FrameRecipe+Mattes.swift` 64 |
| T15 | `0aca690b` | `// MARK: - Containers` … `ReelWebM`; `// MARK: - Graphics` … `ReelGraphicPackage` | `ReelCore.swift` 766 → 439 | `ReelCore+MediaFiles.swift` 207, `ReelCore+Graphics.swift` 131 |
| T15c | `08c3d8d5` | `ReelAgentSocket.answer(_:)`; `AgentServer.swift:806` calls it | `ReelCore.swift` 439 → 445; `AgentServer.swift` 807 → 807 | — |
| T16 | `650d5548` | `writeTiles` in `MediaImporter+Thumbnails.swift`, the arm calls it | `MediaImporter.swift` 589 → 585; `+Thumbnails` 120 → 140 | — |
| T17 | `bf2ef660` | `// MARK: - Settings` (`dimensions`, `videoSettings`, `sliceDuration`) in `extension ReverseRenderer` | `ReverseRenderer.swift` 574 → 479 | `ReverseRenderer+Settings.swift` 98 |

- **Pure moves (T11–T15, T17):** each moved range diffed empty against `git show
  HEAD:app/Sources/<Old>.swift` before its commit (T17 after normalising its three `private static
  func` lines), and each old file's `git diff --numstat` showed only the named edits: T11–T14
  added 0 lines; T15 added 13 (the header's 11 for its 8, and `takeErrorMessage` and `takeString`
  losing `private`); T17 added 1 (`bufferBudget` losing `private`). Widened, and nothing else:
  `takeErrorMessage`, `takeString`, `ReverseRenderer.bufferBudget`, `dimensions(of:track:limit:)`,
  `videoSettings(_:fps:intermediate:)`, `sliceDuration(dimensions:fps:)`. `ReelCore.swift` is 445,
  not the road map's ≈442: T15's header (first sentence and type list naming the ReelCore files,
  "the typed patches" dropped) is 3 lines longer than the old one.
- **The refactors (T15c, T16), not line-identical:** T15c's `answer` is exactly `text.withCString
  { rc_agent_string_create($0) }`, a plain static; after it `git grep -n 'rc_[a-z_]*(' --
  app/Sources` matches only the ReelCore files, `ReelOpSchema.swift:28` and `ReelOps.swift:37`
  (doc comments). T16's `writeTiles` is the arm's loop moved with its guard and comment, `nil`
  once superseded; the labelled break stays in `thumbnails`; it is await-free.
- **Typecheck:** `make typecheck` before each of the eight commits: exit 0, 0 errors, the 4
  baseline warnings each time.
- **Anchors re-aimed:** `graphics_ffi_probe.py`'s `frame-off-by-one` → `ReelCore+Graphics.swift`;
  `cache_pass_probe.py`'s `frame-check-ignored` → `writeTiles`' `guard pass?.isCurrent() ?? true
  else { return nil }` in `MediaImporter+Thumbnails.swift`; `precision_proof.py`'s `reverse-main`
  and `reverse-709-labels`, and `log_proof.py`'s `REVERSE_VARIANTS` edits on `MAIN10_LINE`,
  `RATE_LINE` and `PRORES_LINE` → `REVERSE_SETTINGS`. Each counted 1 in its new file and 0 in the
  old by `grep -cF`. The anchors left on `ReverseRenderer.swift` (`reverse-odd-hevc`, `X420_*`,
  `PRORES_EDIT`, `odd-range-ignored`, `export_offset_proof.py`'s M22 and M23) each count 1 there.
- **Probe runs:** `graphics_ffi_probe.py --mutant frame-off-by-one` exit 0 ("MUTANT PASS … P5 FAILED
  in the copy (failed: P5, P9)"); `cache_pass_probe.py --only B0,S1a,S1b` 3/3 at T16;
  `cache_pass_probe.py` whole exit 0, 13/13; `--mutant frame-check-ignored` exit 1 ("caught — S1b
  failed", "changed: 2.jpg, 3.jpg, 4.jpg"). `spec_index_proof.py` 222/222 after §7.4's new row.
  Not run, by the spec: `log_proof.py --variant` and `precision_proof.py --mutant reverse-*` (their
  anchor text is unchanged, only the file; the runs are long).
- **The gate:** `make gate` once, after the last toll: PASS, 437 s (names 0.6 s, typecheck 7.0 s,
  fmt 3.2 s, lint 14.3 s, test 251.2 s, app 160.3 s, from `build/gate/times.tsv`), D25 and D26 ok.
- **Release drive (T15c):** `proof_app.py launch --app release`, then `get_project` over its
  socket answered a `ToolError` ("No project is open. Call open_project or new_project first."):
  the answer crossed the FFI through `ReelAgentSocket.answer`. `grep "Frame Job: "` over its log
  printed nothing; the instance was stopped by its pid.
- **Documents:** `app-file-history.md`'s entries for `ProjectSnapshot.swift`, `ReelCore.swift`,
  `MediaImporter.swift` and `ReverseRenderer.swift`, and a new `FrameRecipe.swift` entry; spec
  §7.4 (row 5, the snapshot row, `FrameRecipe+Mattes.swift`, `writeTiles`; 80 → 81 lines) and
  its index's Lines cell; the stale `MediaImporter.swift:19` ("lives in `ReelCore.swift`" →
  `MediaDescriptor.swift`), `framejob_core.h:5` and `ReelOps.swift`'s two "only file" doc lines.
- **Deviations:** the road map's acceptance line asks for `make gate` after each toll; the lane
  rules ask for it once, with `make typecheck` per toll, which is what ran. T15c's doc is two
  lines (the spec's one line wraps at that indent). The lane's gate ran before this record was
  written; `name_residue.py` was re-run over it, exit 0.

**On `worktree-creator-jobs`.** Cherry-picked after CJ0b's record without conflict: `2789fc16`
(T12), `0af270ae` (T11), `c749fa37` (T13), `f9be4aed` (T14), `4c228361` (T15), `bececc56`
(T15c), `853e17b2` (T16), `d142b505` (T17) and `ef7ad78e` (documents), each toll still its own
commit. `app-file-history.md`, spec §7.4 (81 lines) and its index cell merged beside CJ0c's
entries. `AgentServer.swift` is 808 lines there before and after T15c (CJ0c's T8 added one);
the history entry says so.

**Review.** Verdict pass, one nit: `ReelOps.swift:39`, re-worded by T15, ran to 86 columns.
Fixed at integration: lines 38–40 reflowed (`ReelOps.swift` 1353 → 1354, comment only).

**Map entries, at integration.** `app/CLAUDE.md`: the ReelCore entry names which types are
`ReelCore+MediaFiles.swift`'s and `ReelCore+Graphics.swift`'s, `ReelAgentSocket.answer(_:)`, and
`ReelAV1` as `+MediaFiles`'; the snapshot family lists `VideoProps.swift`, `ClipSnapshot.swift`
and `TrackSnapshot.swift`, with `TransitionSnapshot.audioShape` now `ClipSnapshot.swift`'s;
`FrameRecipe.swift`'s entry names `FrameRecipe+Mattes.swift`; `MediaImporter`'s `+Thumbnails`
names `writeTiles`; a `ReverseRenderer+Settings.swift` entry replaces `+Read`'s next-seam
clause. Root `CLAUDE.md` already named the ReelCore files (CJ0a). `make gate` on
`worktree-creator-jobs` after the picks, the fix and these edits: names, typecheck (the four
baseline warnings), fmt, lint, test and app (D25, D26 ok) each `pass` (`build/gate/times.tsv`:
0.6 s, 6.6 s, 3.0 s, 1.6 s, 167.3 s, 139.9 s), "gate: PASS 320s".

**Owed.** Nothing: no proof rows, mutants beyond T16's re-aimed one (run above), or manual
checks, and nothing to file.

#### Every spike, with its rule

Each rule is fixed here before its run (CJ-7). Instruments go in `tools/proof/creator_spike/` (CJ,
VR, SW), `transcript_spike/` and `retake_spike/` (TX), `cursor_spike/` (CU) and `cutout_spike/`
(CO), probes built through `tools/proof/swift_build.py`; each run's `results.json` stores
`rule_sha256` (CJ-7), the OS build and the compute device. A spike's verdict is recorded in its
phase's record and in the decision it feeds before the phase's code. Runs that need power run on AC
(`pmset` first).

**The analysis set (CJ-S2, CJ-S3, CJ-S4 hold the only rules for device, rate, size, log input,
playback impact and shots; VR1 and CO1 re-run their rows for their own kinds.)**

- **CJ-S1 — The clip ceiling** (at CJ6's head; decides CJ-9). How many clips can a project hold
  before editing, planning, drawing or undo stop being usable? Projects of N = 4,096, 8,192, 16,384
  and 32,768 one-second media clips over four tracks of one media, generated as packages; N above
  4,096 needs a scratch Release build with the cap raised, never committed. Measured: (1)
  `rc_project_apply` of `split` at the middle, median of 20; (2) `rc_project_from_json` plus
  `rc_composition_plan`; (3) `frame_recipe` at 20 random times, median; (4) over MCP, one
  `ripple_delete_ranges` of 100 ranges and its undo, each from the call to its answer; (5) after
  (4), the time until the next main-thread call (`get_project`) answers; (6) after an edit, the time
  until `play_preview` composes its first frame; (7) a probe that lays out and draws a
  `TimelineView` of N clips offscreen at the fit-all and the default zoom, median of 20; (8) the
  app's resident memory after 50 undo steps of `split`. **Rule:** N_max is the largest N for which
  (1) ≤ 50 ms, (2) ≤ 500 ms, (3) ≤ 2 ms, (4) applies and undoes in ≤ 1 s each, (5) ≤ 1 s, (6) ≤ 2 s,
  (7) ≤ 33 ms at both zooms, and (8) grows by at most a sixteenth of physical memory. N_max > 4,096
  → CJ6 raises the ceiling to N_max; otherwise CJ-9 keeps 4,096 and CJ6 ends with the verdict and no
  code.
- **CJ-S2 — Vision on video** (at CJ3's head; decides CJ-30 and CJ-32). On which device, at what
  rate and size, and from which reader are Vision kinds deterministic, fast enough and accurate?
  Inputs: the face fixtures always; S-TH1…S-TH4 when they exist. Measured: the cache bytes of three
  runs on each of CPU, GPU and Neural Engine; seconds per minute of source for decode, rectangles,
  and rectangles with landmarks, at long sides 720, 1280, 1920 and native; face recall (the share of
  samples, in spans where a face is known present, with a box overlapping it) at each size; recall
  and reader cost raw against converted on each log or HLG sample; face share over S-TH1's first 60
  s. **Rules:** (1) **Device:** the fastest of the three whose three runs are byte-identical; if
  none is, the CPU when it meets rule 2's rate; otherwise the fastest, with every proof comparing
  against the cache only. (2) **Rate:** 10 samples a second if decode plus rectangles plus landmarks
  run at least 3× real time on 1080p30 and 1.5× on 4K30 on the chosen device; else 5; else 2.5. (3)
  **Size:** the smallest long side of 720, 1280 and 1920 whose face recall is at least 98 % of
  recall at native size, on the small-face fixture and on S-TH1 when it exists. (4) **Landmarks**
  stay in `faces` if they cost at most 2× rectangles alone; else mouth opening is a `mouths` kind on
  the same grid, built by SW8. (5) **Log and HDR input:** the converted reader, unless on every log
  or HLG sample raw recall is at least 98 % of converted recall AND the converted reader costs more
  than 1.5× the direct one per frame (CJ-S3's figure); then face kinds read raw. With no such
  sample, converted. (6) **Face share** on S-TH1's first 60 s below 95 % stops VR1 and SW8 until
  CJ-30 is amended; without S-TH1 the row skips by name and is owed in CJ3's record. VR1 re-runs
  rules 1–3 and 5 for its requests; CO1 re-runs rule 1 for its mask request.
- **CJ-S3 — The lane** (at CJ2a's head; decides CJ-21 and CJ-23; replaces CO's former CO-S4). What
  does decoding for analysis cost, does a second concurrent picture job pay, and does analysis cost
  playback? On a 4K HEVC 10-bit HLG file and a 1080p H.264 file (synthetic until S-TH4 exists):
  frames a second through the direct and the converted reader at long sides 256 and 1280; the total
  throughput of one job and of two; `play_preview`'s composed frames over 20 s of a 1080p30 timeline
  idle and with a `shots` job running. **Rules:** (a) **width:** 2 only if two jobs reach at least
  1.5× one job's throughput; else 1. (b) **playback:** when composed frames with a job running fall
  by more than 2 % against idle, the picture queue pauses while any transport plays and resumes when
  none does. CJ3 (`faces`), CO1 (`masks`) and VR1 (`subjects`) each re-run (b) with their own job at
  their head; the first failure turns the pause on for every picture kind, recorded as an amendment
  of CJ-21. (c) **reader:** converted for converting media and direct for the rest, unless CJ-S2's
  rule 5 says otherwise for a kind.
- **CJ-S4 — The shot signature** (at CJ2a's head; decides CJ-24). Which signature, threshold T and
  neighbourhood m find hard cuts inside one flattened clip? Candidates: a 32-bin luma histogram of a
  64 × 36 downscale, and a 4 × 4 × 4 colour histogram at long side 256, both by L1 distance. Inputs:
  the shots fixture; a no-cut talking head (S-TH1, else ten minutes of the moving-still fixture);
  flattened exports with known cut lists (the trial's exports when they exist, and always a fixture
  project of 40 clips cut from four `testsrc` variants, exported by Frame Job, its cut list read
  from `get_project`). **Rule:** the signature and T with the highest recall on the flattened
  exports with at most one false cut per 10 minutes on the no-cut input; m the largest of 4, 6, 8
  and 12 frames that loses no true cut on the fixture. It passes at recall ≥ 98 %. If no candidate
  passes, a 64 × 36 luma sum of absolute differences joins as a second signal and the run repeats;
  if that fails, CJ-24 ships with the measured recall stated in the guide.

**TX.**

- **TX-S1 — The fill's cost** (at TX1's head; no owner media needed). How fast does `SpeechEngine`
  recognise long speech on this Mac, can one run cover a whole file, and does a fill slow playback?
  A probe calls `SpeechEngine.transcribe` on `say` phrases joined into 10- and 60-minute files, and
  on S-TH1 and S-LONG1 when they exist; it measures wall time, peak added memory, temporary WAV
  size, word count, each word's start against the same audio recognised as six 10-minute windows
  (median and p95 |Δ|), and, in the Release app over MCP, `play_preview`'s composed frames over 10 s
  of a 1080p timeline while a 60-minute fill runs at `.userInitiated`, then at `.utility`, each
  against 10 s idle. **Rules:** outcome A, one whole-file run per media (TX-12), if the 60-minute
  run finishes within 6 minutes and its peak added memory is at most 1/32 of physical memory;
  otherwise outcome B, per-clip windows from the playhead outward. The fill keeps `.userInitiated`
  if `play_preview` composes at least 95 % of its idle count during it; else `.utility` if that
  reaches 95 %; else the fill pauses while the transport plays. The measured rate replaces "a few
  seconds per minute" in the guide.
- **TX-S2 — The view** (at TX2a's head). Which view holds a three-hour transcript and leaves the
  transport keys to the editor? Candidates in order: (b) a custom `NSView` laid out by TextKit 2
  (`NSTextLayoutManager` over `NSTextContentStorage`, viewport layout); (c) an `NSTableView` of
  paragraph rows; (a) a read-only `NSTextView` subclass. Fixture: 27,000 synthetic words in 900
  paragraphs with 40 collapsed cuts and 300 strikes, in the offscreen harness on the main thread.
  Measured: first layout of the visible part, a full rebuild after an edit, moving the highlight,
  hit-testing a click, a selection across paragraphs, added memory. **Rule:** take the first of (b),
  (c), (a) that meets: first layout ≤ 200 ms; rebuild ≤ 100 ms; highlight ≤ 2 ms; hit-test ≤ 1 ms;
  added memory ≤ 1/256 of physical memory; Space and J/K/L reach `handleEditorKey` with no change to
  a frozen file. (a) meets the last only with a change to `handleEditorKey`'s first line
  (`EditorViewController.swift:713`), so it is taken only if (b) and (c) both fail, and that one
  line is recorded as TX-21's deviation.
- **TX-S3 — Cut edges** (at TX3's head). Where should a word's cut fall, when on-device word ranges
  tile the audio and start 270 ms early? Fixtures: (1) `say` phrases joined by silences of 60, 120,
  250, 500 and 1,000 ms (every onset known); (2) the owner's o2 (`tools/proof/media/filler-sample/`,
  29.4 s); (3) S-TH1 and S-RT1 when they exist. Rules compared: E0 the transcript's edges; E1 E0
  corrected by `CaptionPages.lead(for:)`; E2 onset-to-onset from the voice cache as TX-30 words it,
  with E1 as its fallback, at guards of 0, 32, 64 and 96 ms. Measured: per boundary on (1), a
  clipped onset and the error against the true onset; on (2) and (3), the share of edges in
  voice-cache non-speech and under −40 dBFS in the peak cache. **Rule:** E2 with the smallest guard
  that clips no onset on (1) and keeps at least 95 % of real-speech edges in non-speech; else E1 if
  it clips none on (1); else E0, with JOB-11 the only judge. TX-30 records which.
- **TX-S4 — The retake rule** (at TX7's head; needs S-RT1, with its `say` twin as the synthetic
  half). Which phrase split, window and similarity find planted retakes and restarts without
  striking the traps? The script and its answer key are `tools/proof/retake_spike/SCRIPT.md`: 8
  retakes, 8 restarts, 6 repeats and 6 traps (an anaphora, "that that", a refrain, a list). Both
  reads are recognised on this Mac; AssemblyAI only if the owner allows the paid run. Grid: pause P
  {0.4, 0.6, 0.8 s}; window K {2, 3}; similarity θ {0.5, 0.6, 0.7, 0.8}; one-word repeats {off,
  pause-separated}. **Rule:** among the settings that strike no trap word on either read, take the
  highest recall of retakes plus restarts on the owner's read, ties to the higher θ; if that recall
  is under 80 %, the retake kind ships off by default. If no setting strikes no trap word, the
  retake kind ships off, and restarts and repeats ship on at the setting with the fewest trap
  strikes on both reads together, ties to the higher θ. TX-71 records the setting; its strikes on
  S-TH1 go to JOB-14.

**CU** (CU-S1…CU-S4 run in CU0b; rows whose grant is held by a launched `.app` run in a scratch
hardened-runtime bundle opened with `open -a`; rows that post input skip by name without
Accessibility for the poster, and the owner's one run covers them).

- **CU-S1 — Capture APIs, grants, clocks, the cursor's image.** Rows: A1 a listen-only `CGEventTap`
  (session) for mouse down/up, dragged and scroll, no grant; A2 the same tap for keys with no grant,
  Input Monitoring only, Accessibility only; A3 `NSEvent` global and local monitors, the same
  matrix; A4 `CGEvent(source: nil)?.location` polled at 120 Hz (µs per call, whether
  `CGWarpMouseCursorPosition` moves are seen); A5 `NSCursor.currentSystem` over TextEdit's text, a
  Safari link and a resize edge (identity, hot spot, reps, ms per call with a TIFF hash, the safe
  thread, whether it answers nil); A6 event timestamp against arrival `mach_absolute_time`, as ns,
  mach units and `systemUptime`; A7 keys delivered while the probe holds `EnableSecureEventInput()`;
  A8 whether the signed bundle needs a plist key or entitlement for ListenEvent, and whether a tap
  made before the grant works without a relaunch; A9 hidden cursors (a helper's `NSCursor.hide()`,
  TextEdit's `setHiddenUntilMouseMoves`): what `currentSystem`, its image and `CGCursorIsVisible()`
  report, 10 trials each (`CGCursorIsVisible()` is deprecated since macOS 10.9, "No longer
  supported", `CGRemoteOperation.h:203–204` in the macOS 26.2 SDK: the probe calls it for the
  record and carries that warning, which never reaches `app/Sources`; its answer alone never
  satisfies the hidden-span rule below); A10 a replacement for `currentSystem`: two 64 × 64 pt
  `SCStream`s around the pointer, `showsCursor` on and off, differenced, the silhouette's IoU
  against A5's image, 10 trials over three cursors; A11 the grant's API, in the signed,
  launchd-launched scratch bundle on macOS 26, each pair from a clean TCC state (`tccutil reset
  ListenEvent` on the scratch bundle id only): `CGPreflightListenEventAccess()` with
  `CGRequestListenEventAccess()`, and `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` with
  `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` (`IOKit/hidsystem/IOHIDLib.h:147–171`; a
  developer-forum report on macOS 15 has the app missing from the pane after the CoreGraphics
  request, and Apple's answer there names `IOHIDRequestAccess`), measuring whether a prompt
  appears, whether the app is then listed in Privacy & Security ▸ Input Monitoring, whether each
  check reads a grant made in the pane, and whether a tap made after the grant needs a relaunch.
  **Rule:** positions are polled (A4) if a poll costs ≤ 20 µs median and
  sees warps and real moves, else they come from the click source; clicks and scrolls use the tap if
  it delivers ≥ 99 % of 200 events with no grant (Frame Job's own windows included), else the
  monitors if they do, else **STOP** (clicks not captured; the owner is asked before CU1a, and the
  recommendation put is: record positions only, Auto Zoom plans on the pointer's dwells and, if
  CU-S3 passes, on dirty rects, and ripples are not offered); keys use the tap under Input
  Monitoring alone, else the monitors, and if keys need Accessibility **STOP key capture** (the
  owner is asked; recommended: CU6 and CU8 are not built and are filed with A2's and A3's numbers,
  CU9b finds typing from CU-S3's dirty rects if it passed and is filed too if not, and Accessibility
  is never asked, CU-3); the grant's calls (A11) are the first pair that shows a prompt and lists
  the app in the pane, the CoreGraphics pair first on a tie, and if neither lists the app the
  panel's Record shortcuts row opens `Privacy_ListenEvent` with "Add Frame Job with +" in its
  note; the image sampler asks at most 10 times a second
  plus once per mouse-down, `cursor_image=current-system` if A5 identifies another app's I-beam and
  pointing hand in ≥ 9 of 10 trials and its median cost × 10 Hz is ≤ 1 % of one core (≤ 1 ms a
  call), else `none` (no images; the cursor draws as Frame Job's arrow); whatever the verdict, every
  sample is checked for nil at run time, a nil records no change, and a segment whose every sample
  was nil writes `cursor_image: none` and says so on landing; hidden spans are recorded if a signal
  from A9 tells hidden from shown in ≥ 9 of 10 trials in both cases, else not (Hide when idle is the
  remedy); A10 is built only if A5 fails and its IoU is ≥ 0.9 in ≥ 9 of 10 trials
  (`image_fallback=a10`), else the arrow stands and an issue is filed with A10's numbers; the event
  clock is the hypothesis whose arrival − event lies in [0, 20 ms] for ≥ 99 % of events; secure
  input's delivered keys are noted, and the recorder drops keys under `IsSecureEventInputEnabled()`
  either way. Verdict line: `VERDICT positions=<poll|events> clicks=<tap|monitor|STOP>
  keys=<tap|monitor|STOP> cursor_image=<current-system|none> hidden=<recorded|not-recorded>
  image_fallback=<a10|arrow> event_clock=<ns|mach|uptime> secure=<withheld|delivered>
  relaunch=<needed|not-needed> grant_api=<cg|iohid> listed=<yes|no>`.
- **CU-S2 — From global points to movie pixels, and the time anchor.** In the picture: record with
  `showsCursor = true` over a flat-colour full-screen window, the burned tip found per decoded
  frame, the cursor warped along a known path, every frame's `SCStreamFrameInfo` and the polled
  samples logged. Separate's exact configuration (`showsCursor = false`, `showMouseClicks = false`,
  420v): the truth is the instrument's own 24 pt marker moved to the warped point at each step.
  Still start: the screen held still 2 s while the cursor moves, then a full-screen colour flip at a
  logged host time, recording which anchor the segment used and its error. Sources: a display at
  Nominal and at Best (2×); the instrument's window moved and resized; a window of odd size (1001 ×
  701 pt at 1×); a picked window; a second display when attached; each in both configurations.
  Candidates: **M1** `pixel = (p − screenRect.origin) × contentScale × pixelsPerPoint +
  contentRect.origin × pixelsPerPoint`, pixelsPerPoint the configured pixel width ÷ point width;
  **M2** M1 with `scaleFactor`; **M3** a fixed display frame from `SCDisplay.frame`; anchors E2, E1
  and `DisplayTime` of the first complete frame. **Rule:** the mapping is the first of M1, M2, M3
  with tip error ≤ 1.5 movie px at p95 on every source row (odd window included) over still frames;
  the anchor is the first of E2, E1, DisplayTime with time error ≤ one frame interval at p95 on
  every row of BOTH configurations (position error ÷ speed over moving frames); E1's still-start
  error over 10 runs ≤ 25 ms at p95, else the limit is recorded and the file still names E1.
  **STOP:** if no mapping passes for window sources, window recordings keep the burned cursor and
  the panel greys Separate for Window; if none passes for displays, the drawn cursor stops after
  CU1b; if a candidate passes In the picture but fails Separate, In the picture is the default
  (CU-36). The owner is told in each case, with this recommendation for the display STOP: the
  cursor file stays as data on In the picture recordings, read through the candidate with the
  smallest error (recorded; Auto Zoom's targets, the overlays, Speed Up Typing and VR5's follow
  need tens of pixels, not 1.5), and the drawn cursor (CU3a2, CU3c's Separate, CU4's style rows,
  CU11's cursor blur) is filed with the measurements.
- **CU-S3 — Do dirty rects locate typing?** Records the instrument's own `NSTextView` while text is
  inserted programmatically, beside distractors (the menu-bar clock, a spinner, a playing
  animation); per burst the median centre of the per-frame dirty-rect bounding boxes against the
  caret rect. **Rule:** pass if within 64 pt of the caret in ≥ 9 of 10 bursts: the file stores each
  complete frame's dirty bounding box and CU7 aims typing zooms at their median centre; otherwise
  nothing about dirty rects is stored and typing zooms aim at the last click before the burst, else
  the cursor's position at its start.
- **CU-S4 — The file's size and speed.** The core's reader prototype over a worst case: one hour at
  120 Hz (432,000 samples), 3,600 clicks, 20,000 key marks, 40 images, each figure measured through
  a JSON request and answer as `rc_cursor_query` runs it. **Rule:** a JSON body (columnar integer µs
  and points × 100) if the file is ≤ 25 MB, parse and validate take ≤ 300 ms, and `state at t` takes
  ≤ 20 µs median once prepared; otherwise a binary columnar body (little-endian i64 arrays after a
  JSON header), version 1 either way. Smoothing's `prepare` at smoothing 1 takes ≤ 1 s on the
  one-hour file, else smoothing is prepared per 60 s window on demand, off the compositor's thread,
  and the verdict says which.
- **CU-S5 — Motion blur's cost** (before CU11; any time after CU0b). A probe through
  `MetalRenderer`'s pipelines draws one full-canvas layer N times at sub-frame transforms (a 2×
  zoom's middle, eased), accumulated in `rgba16Float`, N ∈ {4, 8, 16}, at 1920×1080 and 3840×2160,
  measuring GPU time against the frame drawn once. **Rule:** ship zoom blur at the largest N in {16,
  8, 4} adding ≤ 4 ms at 1080p and ≤ 8 ms at 4K on the owner's Mac, one N for preview and export;
  **STOP zoom blur** if N = 4 misses either bound (numbers recorded, an issue filed). Cursor blur (N
  sprite samples inside `layerSample`) ships either way.

**CO** (CO-S1 and CO-S2 at CO0; CO-S3 at CO0 when S-KEY1 exists, else at CO4's head; the former
CO-S4 is CJ-S3 (b), re-run by CO1).

- **CO-S1 — Which segmentation, at what rate and read size.** Candidates: person `.balanced`, person
  `.accurate`, `VNGeneratePersonInstanceMaskRequest` with `generateScaledMaskForImage`; each at
  every source frame (capped at 30 a second), at 15 and at 10 a second; frames read at the source's
  size and at a long side of 1920; on the device CJ-S2's rule 1 picks for the mask request (the
  Neural Engine until CO1 re-runs rule 1; a different pick re-measures speed). Truth: S-KEY1's keyed
  composites. Measured on every truth frame against the mask the compositor would show there (CO-3's
  nearest-hold): J = mean IoU of mask > 0.5 against truth > 0.5; B = mean
  |mask − truth| inside an 8 px band around the true edge at 1080p; B on the gesture segment;
  flicker = mean consecutive-mask difference on the still segment; realtime factor at 1080p30 and
  4K30; also S-KEY1's composite re-tagged with a 90° rotation matrix, and the first Vision call of a
  fresh process (recorded, no rule). **Rule:** (a) a candidate whose flicker exceeds 2 levels is
  out; (b) the rate is every frame, unless B on the gesture segment at 15 a second is within 5 % of
  every-frame B (then 15), and again at 10 a second within 5 % (then 10); (c) **Standard** is the
  fastest remaining candidate at ≥ 1.0× realtime at 1080p30 at that rate whose J is within 0.02 of
  the best; if none reaches 1.0×, the rate steps down (every frame → 15 → 10) and (c) is applied
  again; if none reaches 1.0× at 10, Standard is the fastest within 0.02 J at 10 and its realtime
  factor is recorded as a risk; (d) **Best** is the lowest-B candidate, kept only if its B is ≥ 15 %
  below Standard's and it runs ≥ 0.25× realtime, else no Best and no Quality control; (e) the read
  size is a long side of 1920 for a larger source when J and B there are within 0.005 and 2 % of the
  source size's, else the source size; (f) the rotated composite's J is within 0.01 of the
  unrotated, else **STOP**: CJ-23 is amended before CO1 to read coded frames and pass the
  orientation to Vision. Without S-KEY1 at CO0: speed only, on the E9 fixtures and S-TH1 if present,
  Standard = person `.balanced` at the fastest rate (every frame, 15, 10) reaching 1.0× realtime;
  (b), (d), (e), (f) run when S-KEY1 arrives, before CO4.
- **CO-S2 — How the mask reaches the compositor.** A probe compiled from `app/Sources` takes the
  core's plan of a project built through the FFI, adds by hand a mask track whose segments copy the
  picture segments, fills both through `CompositionBuilder.fill`, and reads every frame through a
  probe compositor (a subclass of the class the project would use) that fetches both tracks' buffers
  per request; frame counts from the probe's own `AVPlayer`. Fixture: a synthetic movie whose frame
  k carries its index as a bar code, and mask chunks written from it with chunk-relative times by
  CO-3's nearest-hold rule. Tried: HEVC 8-bit 4:2:0 full range with the mask in luma, then ProRes
  422 Proxy; chunk lengths 5, 10 and 30 s. **Rule:** the mask track is kept when all hold: (1)
  **registration** — every frame shows the mask of the nearest analysed source frame (ties to the
  earlier in the stream its segment reads), at every-frame analysis and at 15 a second, across a
  trim, ×0.5, ×2, ×1.37 with a chunk boundary inside the segment, a ramp across a chunk boundary, a
  freeze, a reverse (mirrored chunks), a split, a nest, a cross-dissolve and an HLG
  variable-frame-rate source (S-TH4, else an `ffmpeg` HLG VFR fixture); (2) **colour path** — the
  value read differs from the DECODED mask by ≤ 1/255 at every pixel in an SDR and an HLG
  composition under the class each is built with (if the plain class conforms the mask, a
  composition with a mask track is built with `ConvertingCompositor` and (2) is measured again); (3)
  **codec loss** — decoded masks' IoU against Vision's (both > 0.5) ≥ 0.995, mean |difference|
  inside the 8 px edge band ≤ 3 levels; (4) **size** ≤ 15 MB per minute of 30 fps source at
  Standard; (5) **playback** — a 1080p30 camera with its mask track over a 4K screen recording
  composes, over 20 s crossing ≥ 5 chunk boundaries, ≥ 99 % of the frames it composes without the
  mask track; (6) **build** — a 60-minute camera cut into 120 clips, every one cut out, builds
  within 100 ms more (median of 10) than without mask tracks. The chunk length L is the shortest of
  5, 10, 30 s passing (5) and (6) whose per-chunk fixed cost adds under 5 % to analysis time per
  minute; the encoding is the smaller of the two that pass. Otherwise the per-media mask pack is
  measured on (1), (2), (5), (6) and kept if it passes; if neither passes, CO stops after CO1 and
  the owner is asked, with this recommendation: the video cutout (CO2a–CO5) is filed with both
  measurements; CO10's cutout of stills and pictures, which needs one mask image per media and no
  track, is built in its place (its dependency on CO4 becoming CO1); CO6–CO9 go on, since layouts
  and hide-while-silent need no mask (CO7's crop centres on the source).
- **CO-S3 — Whether the edge needs refinement, and which.** Candidates: r0 bilinear sampling and a
  smoothstep remap (the edge and feather controls); r1 a joint bilateral upsample in the layer stage
  (3×3 mask texels weighted by the picture's colour distance, read as `KeyReading` reads); r2 a
  guided filter in a pass before the destination at twice the mask's size. A standalone Metal probe
  over S-KEY1's frames and masks measures B on the composites and cost per frame at 1080p and 4K
  (200 frames a sample, three interleaved runs, median of medians). **Rule:** the cheapest candidate
  whose B is ≤ 1.1 × the lowest B ships, if it costs ≤ 1.0 ms at 1080p and ≤ 3.0 ms at 4K above r0;
  if r1 and r2 both miss the cost bound, r0 ships and the better is filed with its numbers.

**VR.**

- **VR-S1 — People and saliency on video** (at VR1's head, after CJ-S2, on CJ-32's device). At what
  rate and frame size do `VNDetectHumanRectanglesRequest` r2 and
  `VNGenerateAttentionBasedSaliencyImageRequest` r2 run deterministically and fast enough, and do
  person boxes hold when the face is lost? Instrument `tools/proof/creator_spike/vr_subjects/`
  (synchronous VN* calls through CJ-23's reader); inputs S-TH1 (with the owner's times for the
  leave, turn-away and side-on beats), S-TH4 (HLG) and the moving-still fixture. **Rules:** (1) the
  rate is `faces`' rate if both requests together, at `faces`' frame size, run at ≥ 4× realtime;
  else every other `faces` sample; (2) the frame size is `faces`' unless person recall there is more
  than 1 point under recall at a long side of 1440 on S-TH1, then 1440; (3) three runs on the pinned
  device give byte-identical files, else **STOP**: the kind's stamp carries a tolerance instead,
  amended before VR1's code; (4) people stay if the person box is found in ≥ 90 % of S-TH1's
  turned-away and side-on samples, else `people` leave `subjects` and VR-21's person tier is removed
  by amendment before VR1's code; (5) with S-TH4, person recall through the converted path is
  recorded (no rule). VR1 also re-runs CJ-S2 rules 1–3 and 5 and CJ-S3 (b) with a `subjects` job.
- **VR-S2 — The planner's first numbers** (with VR2a, over cached analyses, no video). The core's
  planner from a test binary over S-TH1's cached `faces` and `subjects`, T1's and T2's, and the
  canned fixtures; grid dead zone {6, 10, 15} % × speed {0.3, 0.5, 0.8} windows/s × headroom {33,
  38, 42} %; measured containment (the face centre inside the window's central 60 %) and moves per
  minute. **Rule:** the setting with the highest containment at no more than 6 moves per minute; if
  none reaches 97 % containment, the dead zone shrinks one step and the cap rises to 8. JOB-31
  judges the feel.
- **VR-S3 — Face-to-mic agreement** (at VR6's head). Over S-PC3 (a two-shot with a microphone each)
  and the two-face moving still with synthetic turns, the agreement between each face's mouth
  opening and each mic's turns, for the true pairing and the swapped one. **Rule:** the threshold is
  the midpoint between the lowest true-pair agreement and the highest swapped-pair agreement when
  they separate; if they do not, VR6 always asks (VR-61) and the guide says so.
- **VR-S4 — A framing switch in the preview** (before VR7a's code, only on the owner's yes). How
  long does the preview take to rebuild on a canvas-size change on a 300-clip project (measured by
  toggling `set_canvas`), and does a per-framing plan fit the decoder budget? **Rule:** under 1 s on
  the owner's Mac, the preview rebuilds on switch; otherwise it keeps the last two framings'
  compositions. A framing whose plan warns past 8 decoders is named in the export sheet.

**FC** (paid runs behind `--live --cap`, held to P-6's ledger; an Anthropic key is read only by
`assistant_prompt_eval.py`'s `anthropic_key()`; an AssemblyAI request goes through
`tools/proof/cloud_spike/`'s client with `RC_ASSEMBLYAI_KEY` supplied by the owner for that run and
`cloud_live_ledger.py` with its cap; only the owner's own speech is sent, a guest's only with the
guest's agreement, recorded in the spike's README).

- **FC-S1 — Sound Analysis as a signal** (before FC3; verdict FC-30). On macOS 26.5.1, does
  `SNClassifySoundRequest` `.version1` find laughter, applause and cheering in the owner's
  recordings well enough to steer the pool, how fast, and at which window? Inputs: S-EV (with its
  written onset list), at least 10 minutes of speech only (S-TH1 and S-ST1), S-MU, and
  `samples/Rode-usb-mic.m4a`. Runs: windows 1.0, 1.5 and 3.0 s at overlap 0.5, through
  `SNAudioFileAnalyzer` and through `SNAudioStreamAnalyzer` fed by `speechReader`. **Rule:** a group
  is first-class when one threshold t ∈ {0.3, 0.4, …, 0.8}, chosen on the odd-numbered labelled
  events and applied unchanged to the even-numbered ones, finds ≥ 70 % of them (onset within ±1 s)
  and calls at most one window per 10 minutes of the speech-only and music inputs; a group with
  fewer than 10 held-out events is weak by rule. The window kept has the best laughter recall among
  those at ≥ 60× real time, ties to 1.5 s; if none reaches 60×, the slowest acceptable is kept and
  its figure recorded. The stream analyzer is used if its event times agree with the file analyzer's
  within one hop; otherwise the kind's version records which ran and FC-31 is amended.
- **FC-S2 — The ranking's request shape and cost** (at FC5's head; cap $3.00; verdicts FC-50's
  constants, FC-51, FC-63). Questions: (a) does the helper with one app tool `submit_ranking`, no
  deferred tool and `fallbacks` off send a request the API accepts; (b) does `countTokens` of the
  request text fit FC-62's estimate; (c) does `claude-opus-5-5` submit a valid ranking first time;
  (d) what does a run cost against the estimate; (e) does the ranker's `cancel` after a valid
  submission leave no further request? Inputs: S-TH1's transcript, S-ST1's when present, two
  public-domain texts cut into timed sentences at 2.6 words a second (sources in the README); S-PC1
  or S-LONG1 only with the guest's agreement. Ten runs at counts 10, 20 and 30. **Rule:** (a) passes
  if no request is refused; if `TOOL_SEARCH` beside one non-deferred tool is refused, FC5's diff
  adds `search: false`; (b) passes if FC-S3's estimate lies within its recorded margin of
  `countTokens` on every input, else FC-S3's constants are refitted on both spikes' inputs; (c)
  passes if ≥ 9 of 10 runs submit a valid ranking (FC-63's checks) on the first call and 10 of 10
  within two, else FC5's diff adds a one-shot `rank` message using structured output and FC6 is
  designed on it; (d) passes if every run's priced cost lies in [`low`, `ceiling`] computed before
  it, and the 10th and 90th percentiles of output tokens per candidate become `output_low` and
  `output_typical`; (e) passes if each run's `cost` events number exactly its submissions.
- **FC-S3 — Sentence ends, recognition speed and transcript size** (before FC4; cap $0.50; verdicts
  FC-41's on-device rule, FC-62's constants, FC-45's accepted limit). S-TH1 (and S-ST1) transcribed
  on device and once by AssemblyAI (one request per file, with `disfluencies` and speakers; S-TH1's
  also becomes FC8a's filler fixture). **Rule:** on-device sentence ends are usable if ≥ 80 % of
  AssemblyAI's sentence ends have an on-device FC-41 end within 0.5 s and the sentence counts are
  within 30 %; otherwise FC-41's on-device arm drops punctuation and ends a sentence at a word
  followed by a non-speech run of ≥ 0.6 s on `MediaSpeech`'s 32 ms grid (probability under
  `defaultVoiceConfidence`), or at a change of track where two voice clips play at once, measured
  against AssemblyAI's ends too, and the window and `find_clips`' notes say "Edges are approximate
  without a cloud transcript." when the scope has on-device words. The on-device speed (cold and
  from TR-14's cache) is recorded as FC-45's figure beside TX-S1's; `fixed`, `per_word` and
  `per_sentence` are fitted by `countTokens` (free) with the largest residual as the margin;
  `claude-opus-5-5`'s `max_input_tokens` is recorded.

**SW.**

- **SW-S1 — What AVFoundation does with several audio tracks and many channels** (at SW3a's head).
  Fixtures: a MOV and an MP4 with video and three AAC tracks of distinct tones (440, 880, 1320 Hz);
  the same with three 48 kHz LPCM tracks; one with a 44.1 kHz track; a 6-channel 48 kHz 24-bit WAV
  with a tone per channel, without and with a discrete layout; a 6-channel AAC; S-IP1; S-MT1 when
  supplied. **Rules:** (a) **order:** each track k inserted alone and exported as 24-bit WAV through
  Frame Job; if `tracks(withMediaType: .audio)` lists tracks in the container's order and every
  export peaks at track k's tone ≥ 40 dB above every other, stream k is AVFoundation's k-th audio
  track (SW-30), else streams are ordered by track ID and that is recorded (recorded beside it, no
  rule: the LPCM track's export nulled against ffmpeg's `-map 0:a:k`, and the AAC and 44.1 kHz
  tracks' exports nulled against an export of the same track extracted with `-c copy`); (b) **the
  tap:** the tap branch (SW-60) only if `prepare` reports six channels in AVPlayer AND the export's
  `AVAssetReaderAudioMixOutput`, each channel peaks at its own tone ≥ 40 dB above the rest in both,
  and a round trip (a probe tap zeroing all but k, exported through the export's own mix read) puts
  k in both sides within 0.5 dB for every k; else a channel source is a mono copy; (c) **the fold:**
  if today's export puts every tone in both sides within 1 dB of one another and of every other
  tone, AVFoundation's fold stands, else Frame Job folds (SW-61); (d) **cache reads:** if
  `AVAssetReaderTrackOutput` in float, non-interleaved, with no channel-count key delivers all N
  channels for the WAV, the AAC and the iPhone's tracks, passes read a channel directly, else they
  read the copy; (e) **writing:** if `AVAssetWriter` writes a `.mov` with video and three LPCM
  tracks read back as three tracks in order, the reversed copy carries every track, else a reversed
  CAF per stream; (f) real files: record each track's codec, channels, title, track ID and whether
  one buffer decodes.
- **SW-S2 — Several 4K angles, a thousand shots, three hours** (SW0, after CJ0a's question 4 is
  answered yes; again at SW9a on the owner's files). Runs on F-4K, made once behind `--build-4k`
  (about 34 GB, 30–60 minutes of encoding; the owner is asked first); `play_preview` plays at most
  60 s a call, so a longer run is consecutive calls summed. **Rules:** (a) **cuts on one composition
  track:** two 4K30 angles of each codec (H.264 100 Mb/s as the GH5 writes, HEVC Main 10, ProRes 422
  HQ) alternating every 2–8 s, five minutes at Full, and a two-minute HEVC 59.94 pair: ≥ 99 % of due
  frames composed keeps the plan's assignment, else SW2c is built and (a) re-measured on it; (b)
  **rebuild:** a two-hour timeline of four hidden angle tracks (each twelve placements of one
  ten-minute F-4K file), two microphone tracks and a 1,000-shot program track written as package
  JSON; each rebuild after a `roll`, ten times, from `playback_rebuilds`: the median `landed_ms`
  within 1,500 ms, else the figure goes in the guide and a candidate issue in the Performance
  project (no proxies in this road map); (c) **angles at once:** N = 1…4 angle tracks each in a cell
  of a 2×2 grid on a 1080p canvas, under a full-frame program track at 50 % opacity alternating
  among them every 2–8 s (N + 1 decodes), 60 s at Half and Full: the largest N with ≥ 98 % of due
  frames at Half is the viewer's live cell count (N ≥ 4: four live; 2–3: live up to N, the rest
  refreshed when paused; < 2: every cell refreshed only when paused or after a switch); (d) **long
  files:** time to first frame after seeks to 0:30, 1:00, 2:00 and 2:59 in a three-hour 4K file,
  recorded; on S-LONG1, or a generated file behind `--long` after the owner's yes.
- **SW-S3 — Mouth activity on a one-microphone show** (before SW8, after CJ3). On S-PC2 (one shared
  microphone, a camera on each person, a lavalier each), faces from CJ3's `faces` on each
  1080p-or-larger angle; truth is S-PC2's `turns.json`. Agreement over every second the truth labels
  as one person speaking. **Rule:** ≥ 85 % agreement and `faces` at ≥ 4× realtime per angle: SW8 is
  built as SW-81 says; 70–85 %: built with SW-82's hedge; under 70 %: SW8 is not built and a
  candidate issue records the numbers.
- **SW-S4 — The switch's numbers on real speech** (inside SW2a). Fixtures: F-TURNS at bleed −12, −18
  and −24 dB and floors of −55 and −45 dBFS, and a five-minute excerpt of S-PC1 whose truth is its
  `turns.json` (never the loudness feature SW-21 thresholds). Measured on the excerpt: agreement
  over all single-speaker seconds, and false cuts (shots of a person silent for the whole shot).
  **Rule:** SW-21's and SW-22's defaults are the values that place every synthetic cut within τ
  (SW-27) and, among those, maximise the excerpt's agreement; SW2b ships them when the excerpt
  agrees on ≥ 90 % of single-speaker seconds with no false cut of `min_shot` or more, else SW2b
  shows the bleed row by default and the guide names the case; if NO setting places every synthetic
  cut within τ, SW2a stops, each miss is recorded, and SW-21 or SW-22 (the rule, never τ) is amended
  before SW2b's code.

### CJ1 — the key gate

- **What a person gets:** with no Anthropic or AssemblyAI key saved, every command that would send
  to Claude or AssemblyAI is greyed, and hovering it says which key is missing and where to set it.
  Saving the key in Settings enables it at once, with no relaunch. Commands that read results
  already paid for keep working.
- **Head:** none to wait for. Whether macOS shows a disabled `NSMenuItem`'s `toolTip` (no menu item
  in `app/Sources` sets one today) is a thing only a person hovering can see, so CJ1 does not wait
  on it: by default every keyed menu item that is disabled for its key both keeps the sentence as
  its `toolTip` AND gains a title suffix, "(needs your AssemblyAI key)" or "(needs your Anthropic
  key)", set by the validator while disabled for the key and removed when enabled; a sheet's
  button keeps the tooltip alone (a disabled `NSButton` shows its tooltip). JOB-1 looks, and if it
  finds the menu tooltip shows, the owner may drop the suffix in a one-line change (question 4).
- **Decisions (draft):**
  - **CJ-10 — `ModelKeys` is the one test of presence.** `ModelKeys.swift` holds `ModelKey`
    (`anthropic`, `assemblyAI`); `present(_:store:environment:)`, whose defaults are the key's own
    configuration's `store()` and the process environment, so R6-9's and AI-13's proof isolation is
    unchanged and the sheets keep passing their injected store and environment; `sentence(_:)`;
    `refusal(_:)` (a `ToolError` with the sentence); `require(_:)`; the control helper, which
    disables a control and sets its tooltip to the sentence, or enables it and clears the tooltip
    (a menu item also gains or loses its title suffix, CJ1's head); and `didChangeNotification`,
    posted after either key's own notification, the one a keyed surface observes.
    Nothing is memoised (a presence test is one small file read; a memo would be wrong for an
    injected store and stale when another Frame Job writes the key). Every read that decides "a key
    is present" moves here; the senders still read the credential to send it.
    `AssistantSettingsPane.swift:217` words Settings' status line and is not a gate.
  - **CJ-11 — One sentence per key, for tooltips, notes and refusals:** "No AssemblyAI API key is
    set. Set one in Frame Job ▸ Settings… ▸ Transcription." and "No Anthropic API key is set. Set
    one in Frame Job ▸ Settings… ▸ Assistant." They replace `CloudTranscriber.AccessError`'s,
    `TranscribeSheetController.noKeyNote`'s and `AssistantSession`'s words and every bet's own
    (TX-14, FC-70). The environment variables leave the person-facing sentence (they are in
    `docs/developing.md`). R6-17's precedence is unchanged, only its credential arm's words. The
    Assistant tab's no-key row keeps its call to action, which is not a disabled control.
  - **CJ-12 — The keyed table; every keyed tool refuses in its own precedence.** `ModelKeys.keyed`
    lists each keyed feature: its menu selector or control, its tools, its key, and whether it is
    conditional (keyed only when it would send). A tool refuses only where it would send, after its
    own earlier refusals and any answer it can give from a cache; no tool is keyed before its
    arguments are read, so dispatch gains no key check and `AgentServer.swift` takes no line. The
    shipped rows: `transcribe_for_fillers` (order unchanged, a ready media answers with no key);
    `transcribe` with `engine: "assemblyai"` (R6-16, R6-17 unchanged but for the words); Clip ▸
    Remove Filler Words… disabled, with the AssemblyAI tooltip, only when no AssemblyAI key is
    present AND no media in scope has a current filler transcript; Generate Captions' Engine popup
    keeps AssemblyAI enabled (its cloud options must show for R6-16's reuse), and Start, disabled
    without a key unless R6-16 admits the batch, carries the AssemblyAI sentence as its tooltip; the
    Assistant's composer and Send as today, View ▸ Assistant enabled (the tab says how to set the
    key), `assistant_send` refusing in the Anthropic sentence. The bets add rows: TX6's
    `review_transcript {fillers}` and Fillers box, TX7's hand-off, FC7b's Rank.
  - **CJ-13 — The startup parity check gains a sixth part:** every tool `ModelKeys.keyed` names
    exists, and its catalog description names its key. In `AgentServer+Parity.swift`; root
    `CLAUDE.md`'s "FIVE parts" becomes six.
  - Amendment lines: **R6-17** "**Amended by CJ-11**: the credential arm's words are `ModelKeys`'
    AssemblyAI sentence."; **AI-8** "**Amended by CJ-10, CJ-11**: whether the key is present is
    `ModelKeys`'; the failure's words are its Anthropic sentence."; **TR-10** "**Amended by CJ-12**:
    Clip ▸ Remove Filler Words… is disabled, with the key's tooltip, when no AssemblyAI key is
    present and no media in scope has a current filler transcript."
- **Core, FFI:** none.
- **Swift:** new `ModelKeys.swift`. `FillerSheetController.swift` (306): `validateFillerAction` asks
  `ModelKeys` and a memoised "any current filler transcript in scope" (keyed by the edited project's
  handle, dropped on the transcript cache's posts). `FillerSheetController+Transcribe.swift` (205)
  and `TranscribeSheetController+Cloud.swift` (345): presence through `ModelKeys` with the sheet's
  injected store and environment; Start's tooltip while disabled for the key.
  `CloudTranscriber.swift` and `AssistantSession.swift` take the sentences.
  `EditorViewController+Assistant.swift:169–171` reads presence through `ModelKeys`. A key saved or
  removed in Settings reaches every open keyed surface at once: the two keys post two different
  notifications (`SettingsWindowController.didChangeNotification` for AssemblyAI,
  `AssistantConfiguration.didChangeNotification` for Anthropic), so `ModelKeys` gains
  `didChangeNotification`, posted once after either (one observer of each in `ModelKeys.swift`,
  installed at launch), and every keyed surface that stays open observes it alone: the Remove Filler
  Words sheet (it observes neither today), the Generate Captions sheet (in place of its observer at
  `TranscribeSheetController.swift:355`), TX6's Transcript bar, TX7's hand-off button and FC7a's
  Find Clips window. A menu item needs none: it validates when its menu opens.
  `AgentServer+Fillers.swift`: the credential arm's words only. `AgentServer+Parity.swift` (195):
  the sixth part. Every keyed tool's catalog description gains its key clause.
- **MCP mirror:** no new tool; each keyed tool refuses in its own precedence (CJ-12).
- **Docs:** `docs/guide/settings.md` (what each key enables, the greyed commands without it),
  `cleanup-tools.md`, `captions.md`, `mcp.md`, `assistant.md`; spec §4.3c, §7.9a/§7.9e (the keyed
  refusal's place, the sixth parity part), §9 (keyed items validate off); root `CLAUDE.md` (six
  parity parts; the rule "A feature that needs a language or cloud model tests its key through
  `ModelKeys` (spec §11 CJ-3)"); `app/CLAUDE.md` (`ModelKeys.swift`); `docs/developing.md` (the
  proofs' variables); `docs/manual-checks.md` (JOB-1).
- **Acceptance:** `make gate`; `keys_probe.swift` and `keys_proof.py` PASS against Release; the old
  sentences' pins re-pinned in `cloud_captions_probe.py`, the filler proofs and the assistant lane
  proof (named in the record).
- **Proof rows** (`keys_proof.py` over MCP with `-RCSecretFolder` on an empty scratch folder and
  both variables unset, then dummy keys with `assemblyai_fake.py` and the assistant's stand-in;
  `keys_probe.swift` through `swift_build.py`):
  - K1: with no key, `transcribe_for_fillers` refuses a bad media id for the id, then a media with
    no filler transcript in the AssemblyAI sentence; a media with a current filler transcript
    answers `ready: true`; `transcribe` with the cloud engine refuses in R6-17's order; the stand-in
    records zero requests.
  - K2: with a dummy key and the stand-in endpoint, the same calls reach the stand-in.
  - K3 (probe): each keyed menu item over an empty `MemoryStore` validates off with its tooltip the
    sentence; over a `MemoryStore` holding a key, on with the tooltip cleared.
  - K4 (probe): `present` follows a scratch `FileStore` written and emptied between two calls, with
    no relaunch and no notification.
  - K4b (probe): with the Remove Filler Words sheet and the Generate Captions sheet open over an
    empty `MemoryStore`, posting `SettingsWindowController.didChangeNotification` after a key is
    written enables each sheet's Transcribe or Start control and clears its tooltip without
    reopening; posting `AssistantConfiguration.didChangeNotification` reaches `ModelKeys`'
    notification the same way (FC7a's and TX6's rows repeat this for their surfaces).
  - K5: Remove Filler Words with no key and a current filler transcript validates on
    (`perform_menu_item` opens the sheet); with neither, off.
  - K6 (probe): Generate Captions over an empty store: the AssemblyAI item enabled; Start disabled
    with the sentence as its tooltip without a reusable transcript; enabled with no tooltip with one
    (R6-16).
  - K7: no "Frame Job: " line at launch; the probe runs the sixth part over the shipped catalog and
    over a copy with one keyed tool's clause removed, which it must name.
  - K8: View ▸ Assistant stays enabled with no key; `assistant_send` answers the Anthropic sentence.
- **Mutants** (9): `present` ignores the environment variable (K2); the credential read moved ahead
  of the ready arm in `transcribe_for_fillers` (K1); a presence memo never dropped (K4); the cached
  transcript arm removed from the menu validator (K5); the tooltip not set on disable (K3); the
  title suffix not removed on enable (K3); Start's tooltip not set (K6); `ModelKeys` not observing
  the AssemblyAI pane's notification (K4b); the sixth parity part removed (K7).
- **Manual check:** **JOB-1** — with no keys, open the Clip menu and the keyed sheets and hover each
  greyed AI control: whether the tooltip appears on the disabled menu item (recorded, deciding
  question 4) and reads whole on a sheet's button, and the title suffix reads well; save a key in
  Settings with the sheet open and the item enables without relaunching or reopening.
- **Depends on:** CJ0a. **Lane** A.
- **Questions for the owner:** (1) Remove Filler Words with no key but a current filler transcript
  stays usable? *Recommended: yes* (already paid for, R6-16's posture). (2) View ▸ Assistant stays
  enabled with no key? *Recommended: yes* — the tab says how to set the key. (3) The sixth parity
  part? *Recommended: yes*. (4) A disabled keyed menu item's title gains "(needs your AssemblyAI
  key)" or "(needs your Anthropic key)" beside its tooltip? *Recommended: yes, by default*; if
  JOB-1 finds macOS shows the tooltip on a disabled menu item, the suffix may be dropped.

#### CJ1's record (2026-11-01)

**Landed.** The key gate (spec §11 CJ-10…CJ-13, recorded before the code with the owner's four CJ1
answers: Remove Filler Words usable over a current filler transcript, View ▸ Assistant enabled, the
sixth parity part, the title suffix). Lane A, base `eb350b86`: the code, proofs and documents in
`e0ebb8c3`, the review pass in `5a58bf43`, landed on `worktree-creator-jobs` as one commit after
CU2. No core, FFI, header or format change. Every count below is a `wc -l` or a run's own output.

- **Swift:** `ModelKeys.swift` (new, 218 lines): `ModelKey`, `KeyedFeature`, `ModelKeys`
  (`present`, `sentence`, `refusal`, `require`, `mark` of a control and of a menu item,
  `baseTitle`, `clearSatisfiedMarks`, `observe`, the one-time relay of
  `SettingsWindowController`'s and `AssistantConfiguration`'s notifications as
  `didChangeNotification`). `FillerSheetController.swift` 306 → 359: the keyed validator
  `validateFillerAction(_:item:)` and `FillerTranscriptPresence`, memoised by handle, selection,
  cache and the transcripts folder's date (CJ-12 in place of the road map's "dropped on the
  transcript cache's posts": that cache posts nothing); the sheet observes `ModelKeys`.
  `FillerSheetController+Transcribe.swift`, `TranscribeSheetController.swift` (its observer now
  `ModelKeys.observe`; the on-device Start through `mark` so a cloud tooltip never lingers),
  `TranscribeSheetController+Cloud.swift` (`noKeyNote` deleted; Start through `mark`, the anchor
  line byte-identical), `CloudTranscriber.swift`, `AssistantSession.swift`,
  `EditorViewController+Assistant.swift`, `AgentServer+Fillers.swift` (the credential arm's words,
  order unchanged) take presence and the sentences from `ModelKeys`. The catalog clauses on
  `transcribe_for_fillers`, `transcribe` and `assistant_send`; the sixth part
  `AgentServer.keyedToolFailure` in `AgentServer+Parity.swift`. Frozen files, wiring only:
  `EditorViewController.swift` one line (the validator arm passes `menuItem`), `AgentServer.swift`
  one line (the parity chain). `make typecheck`: 0 errors, the 4 baseline warnings.
- **Proofs:** `keys_probe.swift` (new, 382 lines) and `keys_proof.py` (new, 575 lines), K1–K8.
  Re-pinned to the new sentence: `cloud_captions_probe.py` (the sheet's `noKeyNote` row now
  `ModelKeys.sentence(.assemblyAI)`, `NO_KEY_NOTE`, the KL rows, the "one source" check now
  `["ModelKeys.swift"]`), `cloud_captions_proof.py` (row 1, `NO_KEY`), `filler_sheet_probe.swift`
  S3, `filler_sheet_proof.py` T4. `assistant_session_proof.py`'s `startswith` and the assistant
  tab's no-key row needed no change. `capture_spike/inventory.json`: `FillerSheetController.swift`'s
  `presentAsSheet` re-pointed 302 → 307. Screen 14b (`designs/screens/`) is `skip`ped: a keyless
  launch with no filler transcript greys its item (CJ-12).
- **Docs:** the guide (`settings.md`'s "What each key turns on", `cleanup-tools.md`, `captions.md`,
  `mcp.md`, `assistant.md`, `menus-and-shortcuts.md`), `docs/developing.md` (keys in a proof),
  `docs/manual-checks.md` JOB-1, spec §4.3c, §7.9a (the sixth part), §7.9b, §7.9e, §9, the
  amendment lines on R6-17, AI-8 and TR-10.

**Measured.** `make gate`: PASS 568 s (names 1, typecheck 6, test 341, app 219; fmt and lint
skipped as unchanged); after the review pass PASS 305 s (names 1, test 303).
Against Release: `keys_proof.py` 11/11; `filler_sheet_proof.py` 15/15; `cloud_captions_proof.py`
225/225. In the loop on Debug: `keys_proof.py` K1, K2, K5, K7, K8 5/5; `filler_sheet_proof.py`
T0–T6 5/5 as run; `cloud_captions_probe.py --only hygiene,chrome,keyless` 148/150, the two failures
untouched by CJ1: "18: the baseline tree's project.yml reads" (under Owed) and "S:
`CloudTranscriber(` is constructed in exactly THREE files", stale since cut-by-transcript CT-3 and
fixed in CJ1's review pass (FIVE files, adding `AgentServer+Fillers.swift` and
`FillerSheetController+Transcribe.swift`; `--only hygiene` 33/33).

**Mutants.** Eleven, one per decision, each run once on the final instrument and each caught (exit 0): probe — `presence-memo` (K4), `control-tooltip-unset` (K6, K4b), `item-suffix-kept` (K3), `start-missing-nil` (K6), `settings-unobserved` (K4b), `no-clause-test` (K7), `memo-without-folder-date` (K5p), `no-menu-reset` (K3b); app, each in a tree copy's Debug build — `present-ignores-environment` (K2), `credential-before-ready` (K1), `no-transcript-arm` (K5). The three existing mutants on anchor lines CJ1 touched, re-run: `filler_sheet_proof.py --mutant transcribe-without-key` caught (S3 failed, exit 0); `cloud_captions_probe.py --mutant keyless-ui-requires-key` exit 1 with its six "KL UI … enables Generate without a key" rows failing, and `--mutant no-credential-check` exit 1 with "KL UI refresh" and "18: with an EMPTY store … Generate is disabled" failing; both builds scored, beside the baseline-history failures named under Owed.

**Review.** Review 1 found one should-fix and two nits. The should-fix: the hygiene row
"`CloudTranscriber(` is constructed in exactly THREE files", in the section of
`cloud_captions_probe.py` CJ1 edits, had failed every run since CT-3; the pass (`5a58bf43`) made
it expect FIVE with CT-3 (TR-10) as the reason (`--only hygiene` 33/33, `make gate` PASS), and
skipped the Release proofs and mutants with reasons, no app source, probe or anchor having
changed. Review 2 passed, the two nits left as nits: `transcribe_for_fillers`' description reads
"…transcript cache and a media no clip plays from its file." as one condition
(`AgentCatalog+Audio.swift`), and screen 14b's edited prose line runs past the file's wrap width.
The CLAUDE.md edits (the root's parity check at six parts, the rule that a model feature tests
its key through `ModelKeys`, `app/CLAUDE.md`'s `ModelKeys.swift` entry) were applied when the
phase landed.

**Owed.** JOB-1 (the owner at the machine): whether macOS shows a disabled menu item's tooltip,
which decides question 4's suffix. Filed as issues when the phase landed: screen 14b's keyless
capture (a `screens.py` fixture with a cached filler transcript, so Remove Filler Words opens
keyless), and `cloud_captions_probe.py`'s "18: the baseline tree's project.yml reads", failing
before CJ1 because its baseline tree is not in the repository (SP3, SP4·off and W fail in a whole
run for the same reason).

### CU0a — scope, decisions, tolls

Bet 2 opens here. Its phases run one at a time in lane B (CJ-6), CO's layout phases after them.
Recordings made before CU3c, imported screen videos and a recording made with Cursor In the picture
behave exactly as today, byte-identical. No feature in this bet uses a language model or a cloud
service, so nothing is keyed; the Assistant can call the bet's tools on its own key as it calls
every tool.

- **What a person gets:** nothing yet; the record and the room.
- **Decisions (CU-1…CU-9), recorded before any CU code:**
  - **CU-1 — The cursor, clicks and scrolls are data; shortcuts are opt-in; the editor draws the
    cursor** (the orchestrator's reading of the owner's "Add all: 1-6" and "The recorder can ask
    for input monitoring", 2026-11-01; CJ0a's question 7 confirms the `recording.md` amendments).
    Zooms, overlays and speed-ups are generated as ordinary edits. No
    cursor is reconstructed for a recording without a cursor file or for an imported screen video;
    no vision pass looks for a pointer.
  - **CU-2 — The cursor file.** One per segment movie, `<movie stem>.fjcursor`, beside the movie in
    `~/Movies/Frame Job Recordings/`. The core owns the format (`cursor_file.rs`'s module doc is its
    specification): Swift writes it and the core reads it back before it is renamed into place.
    Versioned (the core reads every version up to its own and refuses a newer one by name). The
    header carries the stream's content size (points × pixels per point) and `movie_size` (the
    written movie's track size, read back at the segment's close; the encoder rounds an odd
    dimension up). Attached at import as `media.cursor = {path, bookmark?, in_picture}`.
  - **CU-3 — Input Monitoring, the recorder's fourth grant.** Read and asked by the pair CU-S1's A11
    picks (`grant_api`): `CGPreflightListenEventAccess()` and `CGRequestListenEventAccess()`, or
    `IOHIDCheckAccess` and `IOHIDRequestAccess` with `kIOHIDRequestTypeListenEvent`; asked from the
    panel only, when Record shortcuts is on and Record is pressed; asked once
    (`FrameJobInputMonitoringAsked`, counted only in a launchd-owned launch, `launchClause` on every
    sentence), after which each press opens `Privacy_ListenEvent`. `record_screen` refuses `keys`
    without it: "Input Monitoring is not granted to Frame Job. Turn it on in System Settings ▸
    Privacy & Security ▸ Input Monitoring." plus "then relaunch Frame Job." only when CU-S1 says
    `relaunch=needed`, plus `launchClause`. Accessibility is never asked; Frame Job never posts an
    event; no Info.plist key or entitlement unless CU-S1 measures one is needed.
  - **CU-4 — The cursor is part of its clip's layer, not a clip of its own.** The layer stage
    composites the sprite and its ripples over the source texel inside `layerSample`
    (`Compositor.metal:800`), before `gradeSample`, so crop, placement, grade, filters, spotlight,
    obscure regions, mattes, transitions, every transform, zoom action, nest and ramp meet it as
    they met a burned pointer. The sprite binds at `texture(5)` (CJ-8 (b)); no frame copy, no new
    pipeline. The core computes the cursor's source time and state; the compositor draws and never
    opens a file or computes a path (CU-37).
  - **CU-5 — Planners live in the core, and their results are ordinary ops.** Auto zoom, shortcut
    overlays and typing stretches are pure functions of the cursor file and the project, answering
    lists of existing ops (and CU9a's one new op) applied as one named undo step. Nothing is tagged
    "generated"; re-planning finds zooms by content (`action_class.rs`, CJ-8 (i)). A reversed clip
    is refused by name by every planner and by `get_cursor_events` in clip time ("clip C plays
    reversed; <command> plans only clips that play forward"), since mapping it would put a mirror in
    the core (D4-6).
  - **CU-6 — The spikes' rules are CJ0's**, each verdict recorded before the phase that depends on
    it.
  - **CU-7 — Keys are private by construction.** A key-down while ⌘ or ⌃ is held is a shortcut,
    stored with its spelled keys; every other key-down and every auto-repeat is a mark with a time
    and no identity; no character, key code or label of a typed key is ever stored, so none can
    reach a tool answer, the project or the Assistant. Nothing is recorded, not even timing, while
    any process holds secure input (`IsSecureEventInputEnabled()`); a password field that does not
    turn secure input on (a Terminal `sudo` prompt without Secure Keyboard Entry) is recorded as
    time-only marks. No "all keys" mode (it would put typed text, passwords included, into the
    project). The status item shows a mark while shortcuts record (CU-61).
  - **CU-8 — No recorder's code is carried over.** Cap is AGPL-3.0 (the Concat rule applies);
    OpenScreen (MIT) and the rest are not carried either; algorithms are written from their stated
    rules.
  - **CU-9 — The FFI surface is three exports, and their wrapper is a ReelCore file of its own.**
    `rc_cursor_open(bytes, len, err_out)` (parse and validate; a check is an open and a free),
    `rc_cursor_free`, and `rc_cursor_query(tracks, n, project, request_json, err_out)`: every read —
    a frame's state, an image (base64 PNG inside the JSON), events, the path, each planner — is one
    JSON request and answer. The Swift side is `ReelCursor` in `ReelCore+Cursor.swift` (init,
    `deinit`, `query`, about 30 lines), its typed answers in `CursorValues.swift` (no `rc_*`)
    (CJ-8 (l)); no room is paid.
- **Amendments (appended now):**
  - `recording.md`, first bullet: "**Amended by CU-1**: the cursor's path and images, every click
    and scroll, and — opt-in, under Input Monitoring — the shortcuts pressed and the times of other
    key presses are recorded as DATA in a cursor file beside each movie. With Cursor set to Separate
    (the default from CU3c) ScreenCaptureKit draws neither the pointer nor the click ring, and the
    editor draws the cursor as part of the screen clip's layer. Nothing is reconstructed for a
    recording that has no cursor file."
  - `recording.md`, second bullet: "**Amended by CU-2**: a screen recording's movie may carry a
    cursor file, which import attaches as `media.cursor` (one format bump, CU3a1, written only when
    set). It is still imported through `adoptImported` and the two-try placement, there is still no
    source kind and no flag on a clip, and every op, cache and export but the frame recipe treats it
    as the media clip it is."
  - `recording.md`, "The panel asks for the grants": "**Extended by CU-3**: Input Monitoring is the
    fourth grant, read and asked only when the person chose to record shortcuts (CJ-4)."
  - `recording.md`'s voice-over bullet and CAM-4 (3): `record_screen`'s screen-only arguments gain
    `cursor` (CU3c), `keys` (CU6) and `auto_zoom`, `shortcut_overlays`, `speed_up_typing` (CU10),
    refused by name with `source: "voice_over"` (after `include_framejob_windows`) and with `source:
    "camera"`. "No microphone glyph in the menu bar" stands; CU-61 adds the keyboard mark.
  - CAM-9 (3): "**Amended by CU-13**: the watch is on the stream with a camera or with cursor data
    (every display, window or picked recording from CU1b), and besides E2 it records each complete
    frame's geometry when it changes; CAM-9 (6)'s remove-and-re-add around a resume applies whenever
    it is on."
  - The code-doc rule "Show Clicks needs BGRA" (`RecordingSetup.swift:34–38`) is restated by CU-31
    (CU3c).
  - Not amended: G-1, R5-1, AU-2, AI-10, CAM-10 (CO's), D4-6 (the cursor's mirror is
    `ReverseMirror.swift`'s fourth reader), AU-94 (`retime_range` refuses linked clips in its own
    sentence), CI-3 (base-only rows), CO-61/CO-62.
- **Tolls, each a pure move gated alone and checked line-identical:** U1 `RecordingSetup.swift`'s
  grants (249–398) → `RecordingGrant.swift`, re-aiming `recording_probe.py`'s 10f
  (`RecordingSetup+Camera.swift`'s `extension RecordingGrant` unchanged); U2
  `ScreenRecorder.swift`'s `captureStarted` and `failStart` (341–399) →
  `ScreenRecorder+Started.swift` as an extension (`refuse`, `private`, stays; neither moved method
  reads a `private` member); U3 `RecorderPanelController+Rows.swift`'s persisted choice (271–395) →
  `RecorderPanelController+Choices.swift`; U4 `AgentCatalog+Recording.swift`'s `record_screen`
  argument descriptions → `AgentCatalog+RecordingArguments.swift`; U5 `actions_clamp.rs`'s grading
  clamps (169–272) → `actions_clamp_grade.rs`, with `bounded` and `finite_or` (which the moved
  clamps call) and `clamp_wheels` and `clamp_qualifier` (which `clamp_video`, staying, calls at :89
  and :91) becoming `pub(crate)`; `clamp_curves` already is.
  (`VideoProps.swift`, `FrameRecipe+Mattes.swift` and `ReelCore.swift`'s split are CJ0d's.)
- **Acceptance:** `make gate` after each toll. **Proof rows, mutants, manual checks:** none.
- **Depends on:** CJ0a. **Lane** B. **Questions:** none (the non-goals and the grant are answered).

#### CU0a's record (2026-11-01)

**Landed.** Lane B, one decisions commit, five toll commits and one documents commit on the
lane's branch (`worktree-wf_d062fc7a-bc3-11`), base `822973cd`. Nothing a person or an agent
sees changed. Every range was re-read at the base: U1 (249–398) and U5 (169–272) as the road map
says; U2 ends at 398 and U3 at 394, not 399 and 395 (those lines are the type's closing brace);
`RecordingSetup.swift` was 398 lines, not the 396 `app-file-history.md` named.

| Step | Lane commit | What | `wc -l` before → after | New file |
|---|---|---|---|---|
| Decisions | `d0f0f66f` | CU-1…CU-9 in `creator-jobs.md`; the amendments to `recording.md` (three bullets and the voice-over), CAM-4 (3) and CAM-9 (3); the index's rows and Lines cells | — | — |
| U1 | `628af05f` | `// MARK: - The grants` (`RecordingGrant`) | `RecordingSetup.swift` 398 → 248 | `RecordingGrant.swift` 159 |
| U2 | `af9a8502` | `captureStarted`, `failStart` in `extension ScreenRecorder` | `ScreenRecorder.swift` 399 → 341 | `ScreenRecorder+Started.swift` 68 |
| U3 | `7ed6da44` | `// MARK: - The choice, persisted and restored` (`currentChoice`, `persistChoices`, `restoreChoices`, `refreshSizeNote`) | `RecorderPanelController+Rows.swift` 395 → 270 | `RecorderPanelController+Choices.swift` 135 |
| U4 | `abf55650` | `record_screen`'s properties literal as `recordScreenArguments()` | `AgentCatalog+Recording.swift` 390 → 264 | `AgentCatalog+RecordingArguments.swift` 141 |
| U5 | `f1726d50` | `clamp_wheels` … `clamp_level` | `actions_clamp.rs` 405 → 298 | `actions_clamp_grade.rs` 114 |

- **Pure moves:** each moved range diffed against `git show 822973cd:<old file>`: U1, U2 and
  U3 identical; U4 identical once the old side lost 8 leading spaces; U5 different only in the
  two widened `fn` lines. Each old file's kept lines diffed identical too, but for its header
  doc and U5's `bounded` line. Widened, and nothing else: `bounded` (`pub(crate)`),
  `clamp_wheels` and `clamp_qualifier` (`pub(crate)`, because `clamp_video` stays). U2 widened
  nothing; `refuse` stays `private` in the class.
- **Docs the moves made false:** `RecordingSetup.swift`'s header (the grants →
  `RecordingGrant.swift`), `RecordingSetup+Camera.swift`'s pane-URL sentence,
  `ScreenRecorder.swift`'s file list (`+Started.swift`), `+Rows.swift`'s header and
  `RecorderPanelController.swift`'s ("`+Choices.swift` turns them into a `RecordingChoice` and
  back"), `AgentCatalog+Recording.swift`'s header, `actions_clamp.rs`'s module doc, and
  `actions_qualifier.rs`', `grade_check.rs`' and `model_grade.rs`' module docs.
- **Anchors re-aimed:** `recording_probe.py`'s 10f (`holders == ["RecordingGrant.swift"]`) and
  `ask-every-press`, `open-first-press`, `shell-opens`, `mic-denied-asks` and `panes-swapped` →
  `RecordingGrant.swift`; `choice-drops-include` and `persist-drops-include` →
  `+Choices.swift`, with their docstring lines; `camera_recording_probe.py`'s
  `camera-row-persisted`, `format-unpersisted`, `beside-choice-dropped` and
  `beside-unpersisted` and `audio_ap6c_probe.py`'s M1 and M2 → `+Choices.swift`;
  `tools/proof/README.md`'s size-note line → `+Choices.swift`. A scratch script over the three
  probes' `MUTANTS`, after U1 and after U3: 15 anchors, each once in its named file, each
  re-aimed one 0 times in the file it left, and `excludes` and `sync-while-recording` 0 times
  in the new files; 15/15 both times.
- **Typecheck:** `make typecheck` before each of U1–U4: exit 0, 0 errors, the 4 baseline
  warnings each time.
- **Probe runs:** `recording_probe.py --only grants,exclusion` 94/94 at U1 and at U3, `--only
  grants` 67/67 at U2 (10f with `+Started.swift` on the tool side); `--mutant panes-swapped
  --only grants` exit 1 (61/67); `--mutant persist-drops-include --only exclusion` exit 1
  (26/28); `audio_ap6c_probe.py` 5/5; `camera_recording_probe.py --only panel` 28/28, none
  skipped.
- **U4's catalog:** `make app-debug` before and after U4; `agent-catalog.json` parsed equal
  (exit 0). The bytes differ (`cmp` at char 29), a dictionary's key order.
- **U5:** `cargo fmt --check` exit 0; `cargo test --release --test wheels --test curves --test
  hue_curves --test curve_blend --test qualifier --test qualifier_blur --test evaluate_bounds`
  60 passed, 0 failed; `make lint` exit 0.
- **Spec index:** `spec_index_proof.py` 222/222 after the decisions commit and after the
  documents.
- **The gate:** `make gate` once, after U5 and the documents, before this record was
  written: PASS 495 s (names 3.0 s, typecheck 7.7 s, fmt 3.1 s, lint 1.0 s, test 306.5 s,
  app 169.8 s, from `build/gate/times.tsv`), D25 and D26 ok. `name_residue.py` was re-run
  over the record, exit 0.
- **Documents:** `app-file-history.md`'s `RecordingSetup.swift` and `ScreenRecorder.swift`
  entries and new `RecorderPanelController+Rows.swift` and `AgentCatalog+Recording.swift`
  entries; `core-file-history.md`'s new `actions_clamp.rs` entry; spec §7.4's rows 73 and 75
  (81 lines, unchanged), §7.10's `actions_clamp_grade.rs` row and rows 26 and 65 (132 → 133)
  and its index's Lines cell.
- **Deviations:** the road map's acceptance line asks for `make gate` after each toll; the lane
  rules ask for it once, with each toll's narrow checks, as in CJ0b–CJ0d. The road map's U5 row
  says the moved clamps call `finite_or`; they do not, so `finite_or` stays private. U2's and
  U3's corrected ends are above. `RecorderPanelController.swift`'s header doc, outside the
  spec's file list, was edited because U3 made its sentence false.

**On `worktree-creator-jobs`.** Cherry-picked after CJ0d's record without conflict: `d797cb05`
(decisions), `82543c0d` (U1), `4feb9abf` (U2), `659d2c67` (U3), `e0875375` (U4), `acff5d4b`
(U5) and `878cda2b` (documents), each toll still its own commit.

**Review.** Verdict pass, one nit: `RecordingSetup+Camera.swift:10` still said the file stands
apart because `RecordingSetup.swift` "stands near the 400-line cap", false at 248 lines. Fixed
at integration: "stood near the 400-line cap at CR1a" (comment only, 84 lines unchanged).

**Map entries, at integration.** `app/CLAUDE.md`: the `RecordingSetup.swift` entry names
`RecordingGrant.swift` (the grant reads, the press's step, the pane URLs; the one file a System
Settings URL is spelled in); `ScreenRecorder.swift`'s list gains +`Started`;
`RecorderPanelController.swift`'s gains +`Choices`; the `AgentCatalog` +`Recording` clause names
+`RecordingArguments` (`recordScreenArguments()`). `core/CLAUDE.md`: the `actions_clamp.rs` entry
names `bounded` `pub(crate)` and the grading clamps' new home, a new `actions_clamp_grade.rs`
entry follows it, and `grade_check.rs`'s entry names that file for `clamp_wheels`,
`clamp_curves` and `clamp_qualifier`. `make gate` on `worktree-creator-jobs` after the picks,
the fix and these edits: names, typecheck (the four baseline warnings), fmt, lint, test and app
(D25, D26 ok) each `pass` (`build/gate/times.tsv`: 0.7 s, 7.0 s, 3.4 s, 7.7 s, 185.3 s,
135.0 s), "gate: PASS 340s". The Release products the lane's copied build database had removed
from this tree's `build/` (`Sparkle.framework` and five dSYMs) were rebuilt by its app step.

**Owed.** Nothing: no proof rows, mutants or manual checks, and nothing to file.

### CJ2a — the analysis lane, its store and reader, and `shots`

- **What a person gets:** nothing visible yet. An agent gets `get_media_analysis` with the `shots`
  kind: the hard cuts in any media or clip.
- **Head:** CJ-S3 and CJ-S4 run; their verdicts are recorded in CJ-21, CJ-23 and CJ-24 first.
- **Decisions (draft):**
  - **CJ-20 — Analysis is a cache, made on demand.** It never runs at import, is never project
    state, and is never read by the composition plan or the frame recipe; a planner reads it and
    writes ordinary edits. A render drawn from it (CO's masks) is substituted by Swift, as a
    reversed file is (§5.6). No analysis kind bumps the format. The speech cache's import-time rule
    stands for speech.
  - **CJ-21 — One lane, `AnalysisLane`, process-wide, with two queues:** a picture queue (decodes
    and Vision) and a sound queue (audio decodes and Sound Analysis), so a sound job never waits
    behind a face job. Each is its own `DispatchQueue` at `.utility`, never the cooperative pool,
    never `MediaCacheLane`; the picture queue's width is CJ-S3's (1 until it earns 2), the sound
    queue's 1. A job is a source, a window and its kinds; kinds that share a reader, a size and a
    grid decode once (`faces` and `subjects`). Jobs are wanted by owners — a document's command, a
    tool call, an export — as ramp audio's renders are (SR-12): unwanted jobs are cancelled, a job
    wanted again while running is not, `wait` returns on landing, failure or cancellation, and an
    owner's `settled` runs on main. A job takes no `CachePass` and writes only through
    `CacheLedger.publish(in:for: nil)`, so an import pass and an analysis job of the same media
    never cancel or wait on each other. `-RCDevAnalysisHold <s>` (`FRAMEJOB_DEV_TOOLS` only) holds
    each job before its first frame, polling cancellation every 50 ms. When CJ-S3 (b) turns it on,
    the picture queue pauses between frames while any transport plays, through a new internal
    `BackgroundRender.anyPlaying` over its `transports` (:71).
  - **CJ-22 — The store.** A kind's results for one media are a marker `cache/analysis/<kind>/<media
    id>.json` and a payload folder `cache/analysis/<kind>/<media id>/` holding the files the kind
    names (`shots` a `frames.bin`, `faces` a `samples.bin`, CO's masks one `masks.pack` per media
    (CO-4 as CO0 rewrote it), FC's `sound_events` a `windows.bin`). A kind whose variants must coexist puts
    the variant in its name (`masks`, `masks_best`). Every kind has a grid on source time — frames
    by presentation time (`shots`, masks), samples at k / rate (`faces`, `subjects`),
    windows at k × hop (`sound_events`) — and stores per grid point only values that depend on that
    point's input and a fixed neighbourhood the kind names, never on where a job began or what else
    is cached. Thresholds over time, minimum lengths, smoothing and identity are applied when a
    request is answered, over the requested window. The marker holds the `AnalysisStamp`, the
    payload's files and the COVERAGE: the sorted, merged ranges of grid indices stored. A request is
    a hit when the coverage holds every index of its window plus the kind's read margin; otherwise a
    job runs only the missing ranges, each with the kind's pre-roll, and the coverage grows. Payload
    files are written through a `.partial` and a rename, the marker last, all inside
    `CacheLedger.publish`, sorted keys, `.atomic`. The `AnalysisStamp` is the source's identity
    (`CacheStamp`'s size, modified second and duration; no path), the kind and its version (Vision
    request revisions inside it), a digest of the kind's parameters, the OS build, the compute
    device, and the reader's input (`raw`, or the conversion as `ConvertedThumbsStamp` records it).
    A stamp that differs in any field is a miss: the next store deletes the marker first, then the
    payload, and starts empty. Relink, consolidate and `set_media_color` therefore invalidate as for
    every cache. Coordinates are normalised 0…1 in the media's display orientation, origin top-left,
    and every answer carries the display size; times are media source ticks, so any clip, speed,
    ramp or reversal reuses them through `SourceMap` and `ReverseMirror`.
  - **CJ-23 — The frame reader.** `AnalysisFrames.swift` has a direct reader
    (`AVAssetReaderTrackOutput` over the first video track, 32BGRA, scaled to the kind's long edge,
    turned upright from the track's orientation codes) and a converted reader
    (`AVAssetReaderVideoCompositionOutput` over `MediaImporter.oneClip`'s composition at the kind's
    size through step 0, so analysis sees what the person sees; `oneClip`, :311, loses `private`). A
    media whose picture converts (Camera Log, HLG, PQ) is read converted unless CJ-S2's rule 5 says
    otherwise for a kind; frames arrive in presentation order, and a sample at k / rate takes the
    first frame at or after it. CO-7 adds a third arm for masks (CO1).
  - **CJ-24 — `shots`: hard cuts from a deterministic picture difference, no ML.** Each frame's
    signature (CJ-S4's) gives two stored values, d1 (L1 distance to the frame before) and d2 (to the
    frame two before); the pre-roll is two frames. When answered, frame i is a cut when d1(i) ≥ T,
    d2(i + 1) ≥ T (a single flash frame returning to the shot is not a cut), and d1(i) is the
    largest d1 within m frames either side, ties to the earlier. A dissolve, whose distances stay
    under T, is not a cut. T and m are CJ-S4's; the read margin is m + 1 frames each side.
  - **CJ-25 — `get_media_analysis {media | clip, kind, from?, to?}` reads any kind, running or
    reusing it.** Exactly one of `media` and `clip`; with `clip` the window defaults to, and is
    clamped to, the clip's played source window, and each time is also answered in clip ticks
    through its source map and the reversal mirror. It runs off main (`creatorOffMainTools`) and
    waits with a bound fixed here from CJ-S3's throughput, refusing past it with a sentence naming
    how much is covered. It answers `kind`, the source window, the display `size`, `cached`, the
    stamp, `run` (`queued_at`, `started_at`, `ended_at` in process uptime, only when it ran a job)
    and the kind's results. An answer is capped by size; over the cap it is refused naming the
    largest window that fits. It is `get_transcript`'s counterpart for pictures and sounds; every
    kind answers through it.
  - **CJ-26 — A canned analysis is honoured only for a proof:** a marker with `"canned": true`
    carries only the source identity and is read only in a `FRAMEJOB_DEV_TOOLS` build launched with
    `-RCDevAnalysisCanned YES`, so a planner's proof is byte-exact on any Mac and Distribution never
    reads one.
- **Core, FFI:** none.
- **Swift:** `AnalysisLane.swift`, `AnalysisStore.swift` (folders, coverage, hit rule, stamp,
  publish, canned markers), `AnalysisFrames.swift`, `AnalysisShots.swift`,
  `AgentServer+Analysis.swift` and `AgentCatalog+Analysis.swift` (a `creatorHandlers` row and a
  `creatorOffMainTools` name), `ProjectDocument+Analysis.swift` (the document's wants, so
  `ProjectDocument.swift` takes nothing); `MediaImporter+ThumbnailSource.swift`: `oneClip` loses
  `private`; `BackgroundRender.swift`: `anyPlaying`.
- **MCP mirror:** `get_media_analysis` (CJ-25); its comment names the Analyzing sheet's command
  (CJ2b) and `get_transcript` as its counterpart.
- **Docs:** `docs/guide/mcp.md`, `projects-and-media.md` (what `cache/analysis/` holds); spec §5.6,
  §7.4, §7.9e; `app/CLAUDE.md` (the four files and the lane's rule beside `MediaCacheLane.swift`'s);
  root `CLAUDE.md`'s dev launch defaults (`-RCDevAnalysisCanned YES`, `-RCDevAnalysisHold <s>`) and
  its Architecture paragraph, whose "Swift owns windows, gestures, undo, … media import and its
  caches" gains "and on-device analysis of the media (Vision and Sound Analysis on the analysis
  lane, cached per media in `cache/analysis/`; the core reads only what a tool or op hands it)"; the
  counts of CJ-8 (g) for one product tool.
- **Acceptance:** `make gate`; CJ-S3's and CJ-S4's verdicts recorded; `analysis_proof.py` PASS
  against Release.
- **Proof rows** (`analysis_proof.py`; the shots fixture and the flattened export; rows that act
  during a job launch with `-RCDevAnalysisHold 3`): A1 every hard cut of the fixture at its exact
  frame, none elsewhere, none inside the dissolve or at the flash frame; A2 a second call answers
  `cached: true` with marker and payload bytes unchanged; A3 a window inside the coverage is a hit,
  one past it runs only the missing range and the coverage becomes the union; A4 touching the
  media's modification time makes the next call a miss; A5 a `save_project` during a held job lands
  the files after the save, and the next save is not refused as changed by another application; A6 a
  held job whose want is withdrawn (the calling document closed) publishes nothing; A7 two
  documents' calls run one at a time at width 1 (their `run` intervals do not overlap), or overlap
  at width 2 if CJ-S3 earned it; A8 a canned marker ignored without the flag and honoured with it;
  A9 the same window answered after one whole-file call and after two half-window calls in either
  order gives identical `cuts` and equal payload bytes over the shared range; A10 `set_media_color`
  with a Camera Log makes the next call a miss whose stamp names the conversion, and setting it back
  another; A11 an import pass (`relink_media` to the same file) started during a held job completes,
  and the job after it; A12 with `clip`, a trimmed, ×2 and reversed placement answers each cut once
  at its clip time.
- **Mutants** (9): the stamp without the OS build (a probe row); the stamp without the reader's
  input (A10); a write outside `CacheLedger.publish` (A5); a partly covered window taken as covered
  (A3); the read margin not read (A9); width 2 when CJ-S3 said 1 (A7); the flash rule removed (A1);
  canned markers honoured without the flag (A8); the hold not polling cancellation (A6 times out).
- **Manual checks:** none. **Depends on:** CJ0c (T8). **Lane** C. **Questions:** none expected.

#### CJ2a's record (2026-11-01)

**Landed.** Lane C, on the lane's branch (`worktree-wf_d062fc7a-bc3-15`), base `822973cd`:
`bf767308` (`oneClip` internal, the fixtures, the spikes, CJ-20…CJ-27 recorded — before any
`Analysis*.swift` existed), `ecba69a3` (the app code, the probe and the proof), `c15d981c`
(CJ-S3 (b) in CJ-21, the pinned counts, the guide, the spec and the proof README), then this
record's commit. No core, FFI or format change (CJ-20). An agent gets `get_media_analysis`
(`kind: "shots"`); a person sees nothing yet.

- **New files** (`wc -l`): `AnalysisStamp.swift` 183, `AnalysisStore.swift` 221,
  `AnalysisLane.swift` 297, `AnalysisFrames.swift` 385, `AnalysisShots.swift` 218,
  `ProjectDocument+Analysis.swift` 73, `AgentServer+Analysis.swift` 268,
  `AgentCatalog+Analysis.swift` 66, `AgentServer+AnalysisJob.swift` 175 (`FRAMEJOB_DEV_TOOLS`
  only). Wiring: `MediaImporter+ThumbnailSource.swift` (`oneClip` loses `private`, 349 lines,
  unchanged count), `AgentServer+CreatorJobs.swift` 43 → 53 (the handler row,
  `creatorOffMainTools`, `creatorTools()`), `AgentCatalog.swift` 523 → 524 (`catalog +=
  creatorTools()` before `devTools()`), `AgentServer+DevTools.swift` 117 → 120,
  `AssistantPrompt.swift` (`get_media_analysis` in the media topic's tools, no words). Not
  touched: `AgentServer.swift`, `AgentLane.swift`, `ProjectDocument.swift`,
  `BackgroundRender.swift` (CJ-S3 (b) did not fire).
- **Instruments:** `tools/proof/analysis_fixtures.py`, `creator_spike/rule.py`,
  `creator_spike/shots_spike.{py,swift}`, `creator_spike/lane_spike.{py,swift}`,
  `analysis_probe.swift`, `analysis_proof.py` (P1–P9, A1–A12, Z1, ten mutants); `dev_tools.py`
  gains `analysis_job`; `PRODUCT_TOOLS = 107`; `get_media_analysis` in `APP_STATE_TOOLS` of
  `phase9_proof.py`, `recording_proof.py` and `recording_probe.py`.
- **Documents:** spec §5.6 (272 → 286), §7.4 (81 → 82), §7.9c (393 → 410), §7.9e (457 →
  482) and their index cells; the §11 file (216 → 356) and eight index rows;
  `docs/guide/mcp.md`, `projects-and-media.md`, `docs/developing.md`; `tools/proof/README.md`.

**The spikes.** Preflight: `pmset -g batt` "Now drawing from 'AC Power'"; `uptime` at the
start "load averages: 3.49 6.27 8.82", at CJ-S4's last run "41.55 63.44 44.31", at CJ-S3 (a)'s
"11.63 35.50 39.90" (three lanes). OS build 25F80, Apple M2 Max, 12 cores. Both `rule_sha256`
values recomputed by `rule.py` match CJ0a's table (CJ-S3 `209c6f01…ce830`, CJ-S4
`eea6c190…46f9d1`); each `results.json` is in `tools/proof/work/creator_spike/<ID>/`.

- **CJ-S4:** S-TH1 missing, so the no-cut input is ten minutes of the moving still (cover
  SHA-256 `4a0b50f9…038983`) and S-TH1 is owed. The 40-clip project was exported by the Debug
  app (`flattened.mp4`, 1,809 frames, 39 cuts from `get_project`). Recall 39/39 for the colour
  histogram at every T from 0.04 to 0.64 (31 values) and for the luma histogram from 0.20 to
  0.62, false cuts on the still 0 from T = 0.08 (colour) and 0.20 (luma); the tie went to the
  wider band, its median T = 0.34; every m of 4, 6, 8, 12 kept the fixture's four cuts, so m =
  12. PASS at 100 %, no SAD arm. At T and m: the fixture's cuts 60, 120, 180, 240 exactly; the
  photographs' dissolve peaked at d1 0.16; the flash's two sides tie at 2; the VFR twin's cuts
  the same frames. Found: `dissolve_patterns.mov` (test patterns dissolving) peaked at 1.04 and
  answered one false cut at frame 68 — CJ-24's measured limit.
- **CJ-S3 (a), (c):** synthetic files, S-TH4 owed; medians of three in CJ-21. Width 1 (two
  converted jobs 1.05× one). Converted for converting media. `callWaitLimit` = 60 s (26.9 s
  for ten minutes of 4K HLG converted at 256, × 2, up to 10 s).
- **CJ-S3 (b):** on Debug, idle 600 / 580 / 598, busy 593 / 588 / 599, drop 0.84 %: no pause,
  no `anyPlaying`. Each busy run's ten-minute job took 279–319 s in the Debug build (its
  signature loop unoptimised); in Release the fixture's 380 frames took 0.36 s (A1's `run`).

**Commands and results.**
- `make typecheck` after `oneClip` and after each Swift round: exit 0, the four baseline
  warnings, tsc silent.
- `python3 tools/proof/swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS
  tools/proof/analysis_probe.swift`: exit 0.
- `analysis_proof.py --only P1,…,P8`: first 6/8 (P6 and P7 held the tick arithmetic wrong in the
  probe — 4 s is 2,400,000 ticks — and P6 compared the reversed window against a 0 the media's
  extra 200 ticks move); after the fix 8/8.
- Debug, `make app-debug` then `--only A1,A2,A3`: 4/4. The other rows: first A8 (with the flag),
  A10 and A11 failed — the canned marker's coverage was one index short of the media's grid
  (7,600,200 ticks make 381 indices); the converted reader's range ran past the composition
  (-11841); `relink_media` to the file's own path is an identity; and, once those were fixed,
  A10 showed the lane skipping a landed request wanted again after the store had lost it (fixed:
  a request wanted ANEW runs again). Then the whole proof on Debug: 21/21.
- `python3 tools/proof/assistant_prompt_proof.py --probe`: 14/14, F4 "14 topics, 100 tools + 4
  core against 104". `python3 tools/proof/spec_index_proof.py`: 222/222.
  `python3 tools/proof/name_residue.py`: exit 0.
- `make gate`: names, typecheck, test and app `pass` (fmt and lint skipped, no Rust input
  changed), "gate: PASS 352s".
- `RC_PROOF_APP=release python3 tools/proof/analysis_proof.py`: 21/21 (P1–P8, A1–A12, Z1 on
  all three launches).
- `RC_PROOF_APP=release python3 tools/proof/op_argument_proof.py <sock>` on a Release instance:
  first 181/182 — "the core publishes 16 arguments as an opaque object", pinned at 14 since
  before road map "audio" AP10c added `set_track`'s `compressor` and `limiter` (both doors'
  own rows passed); re-pinned to 16 in `op_argument_proof.py`, then 182/182 (107 product tools,
  the dev block with `analysis_job` straight into `import_media`). Parity grep empty.
- Mutants (`analysis_proof.py --mutant <name>`, once each on the final instrument; probe
  mutants on a copy of `app/Sources`, app mutants as Debug tree copies): **nine of ten
  caught** — `stamp-no-os-build` P1, `preroll-by-index` P7 ("119...139 DIFFER at [119, 120]"),
  `stamp-no-reader` A10, `partial-taken-covered` A3, `margin-unread` A9 (the first-half answer
  gained the flash, 150, the other order 151), `width-wrong` A7 (the runs overlapped),
  `flash-rule-removed` A1 (150 answered), `canned-without-flag` A8 (cuts [7] without the flag),
  `hold-no-cancel-poll` A6 (cancelled 3.02 s after t0). **`write-outside-publish` SURVIVED A5**:
  a save of the package takes about 13 ms (measured with a 1 GiB file in its `cache/`: 0.013 s
  and 0.014 s), so a held job never publishes while a save is in flight and A5 cannot see a
  write made outside the ledger; no row of this phase can make that overlap without a dev hold
  on the save (filed below).
- Review fix pass 1: probe row **P9** added — `CacheLedger.saveBegan` on a scratch folder, an
  `AnalysisStore.publish` started on another thread, no marker or payload until `saveEnded`,
  then both — and the `write-outside-publish` mutant re-pointed at it.
  `analysis_proof.py --only P1,…,P9`: 9/9. `--mutant write-outside-publish`: CAUGHT, P9 failed
  ("publish returned true (want false), marker true, payload true"). **Ten of ten caught.**

**Deviations.**
- **The call holds the agent lane's lock while it waits**, as `get_transcript` does; the road
  map's draft said nothing of it and the adversary's objection 2 ruled out releasing it.
- **A5–A7 and A11 act through `analysis_job` (CJ-27)**, because the MCP server answers one
  request at a time; A7's "two documents' calls" are two dev owners' jobs.
- **The VFR neighbour rule:** d1 and d2 are to the previous KEPT frames, the flash test reads the
  next kept frame within m + 1, and the pre-roll is two decoded frames with restarts (CJ-23,
  CJ-24), replacing the draft's "the frame before" and "two frames".
- **The shots fixture's dissolve is between two FlexAudio photographs**, not two of the four
  test sources: a dissolve between flat-coloured patterns peaks above every T with full recall
  (1.04), so A1's "none inside the dissolve" can hold only for a dissolve whose distances stay
  under T, which CJ-24's draft presupposed. The pattern dissolve is measured as a finding
  (`dissolve_patterns.mov`) and stated as a limit in CJ-24, the tool's description and the
  guide.
- **The signature is in whole-pixel counts, its L1 divided once:** the spike's first run on
  normalised floats left the flash's two sides 2 and 1.9999999999999998, so the return frame
  became a cut; integers make them tie, as the tie-break needs.
- **CJ-S4's tie-break** (two signatures at recall 100 %): the one with more T at the top recall,
  then the median T of its band. **CJ-S3 rule (a)** is applied at shots' size on each file
  through the reader rule (c) gives it, every file required.
- **A11 relinks to a copy** keeping the bytes and the modification second (the same source
  identity): a relink to the file's own path is an identity and starts no import pass.
- **The lane's "not run again":** a request an owner wants ANEW after it ended runs again (its
  caller found the store missing it); one an owner keeps wanting (the dev owner's earlier
  requests) keeps its run. Found by A10.
- **`isOpenForAnalysis` is `nonisolated`** (the document is main-actor isolated; an owner's
  `alive()` runs on the lane's threads).
- **The VFR twin's grid** is the importer's rationalised rate, 29842/1000, not 30: P7 compares
  within that grid (gaps at indices 118 and 269, the cut at 4 s at 119).
- **TX1** (lane A) may add the same `creatorTools()` seam and catalog splice; the integrator
  reconciles them (one splice, both groups).

**Files outside the spec's list.** `tools/proof/creator_spike/rule.py` (the CJ-7 hash and the
results file both spikes share); `op_argument_proof.py`'s opaque-door pin (above; the file is
in the list for `PRODUCT_TOOLS`).

**CLAUDE.md edits owed** (the integrator applies them):
- `app/CLAUDE.md`, "The document.", after the `MediaCacheLane.swift` paragraph's bullet: a new
  bullet — "- `AnalysisStamp.swift` · `AnalysisStore.swift` · `AnalysisLane.swift` ·
  `AnalysisFrames.swift` · `AnalysisShots.swift` · `ProjectDocument+Analysis.swift` ·
  `AgentServer+Analysis.swift` · `AgentCatalog+Analysis.swift` · `AgentServer+AnalysisJob.swift`
  — on-device analysis of the media (road map creator-jobs CJ2a, spec §11 CJ-20…CJ-27): a cache
  made on demand in `cache/analysis/<kind>/`, never at import, never project state, never read
  by the plan or the recipe. `AnalysisLane` is the process-wide analysis lane, the analysis
  twin of `MediaCacheLane.swift`'s rule: owners want requests (`want` replaces, an unwanted job
  is cancelled, an owner whose `alive()` is false is dropped at the next 50 ms poll, `settled`
  runs on main), a `.utility` picture queue of `pictureWidth` (1, CJ-S3) and a serial sound
  queue, never the cooperative pool and never `MediaCacheLane`; a job takes no `CachePass` and
  writes only through `AnalysisStore.publish` — a lock per (cache, kind, media) inside
  `CacheLedger.publish(in:for: nil)`, re-reading and merging what is on disk — so an import pass
  and a job never cancel or wait on each other, and nothing in a publish waits on main. A
  stamp is compared field by field (`AnalysisStamp.matches`). `AnalysisFrames` reads direct
  (turned upright) or converted through `MediaImporter.oneClip` and step 0 when a
  `ThumbnailInput` exists, its pre-roll two DECODED frames. `get_media_analysis`
  (`AgentServer+Analysis.swift`, off main) waits holding the agent lane's lock, at most
  `AnalysisLane.callWaitLimit` (60 s). `-RCDevAnalysisHold <s>` and `-RCDevAnalysisCanned YES`
  are dev only, and `analysis_job` (`AgentServer+AnalysisJob.swift`) is the dev tool proofs
  act through."; and in the `MediaImporter.swift` bullet, "+`ThumbnailSource`: the converted
  strip, below;" becomes "+`ThumbnailSource`: the converted strip, below, and `oneClip`, which
  the analysis reader's converted arm builds too;".
- Root `CLAUDE.md`: "for all one hundred and six product tools" → "for all one hundred and
  seven product tools"; in "Verifying a build"'s app-state list, "`detect_fillers`,
  `transcribe_for_fillers`, `get_transcript`," → "`detect_fillers`, `transcribe_for_fillers`,
  `get_transcript`, `get_media_analysis`,"; in its dev-tools list, after the `land_recording`
  sentence's "(spec §11 AU-69); and", insert "`analysis_job`, which wants a media's analysis
  under a document's stand-in owner and returns at once, or waits for every such job and
  answers their runs (spec §11 CJ-27); and `-RCDevAnalysisHold <s>`, which holds each analysis
  job before its first frame, polling cancellation, so a proof can act during it; and
  `-RCDevAnalysisCanned YES`, with which a canned analysis marker is honoured (spec §11
  CJ-26); and"; and in "Architecture", "the Metal compositor, media import and its caches, and
  agent dispatch." → "the Metal compositor, media import and its caches and on-device analysis
  of the media (Vision and Sound Analysis on the analysis lane, cached per media in
  `cache/analysis/`; the core reads only what a tool or op hands it), and agent dispatch."

**To file** (drafts, `ai-drafted`, `low-priority`):
- "Shots: a flash whose two sides differ in its bin, and a dissolve between flat pictures,
  can be answered as cuts" — CJ-24's measured limits: the flash rule rests on the return
  frame's d1 not exceeding the flash frame's (exact only when the flash shares no bin with the
  shot), and a dissolve between flat-coloured pictures moves whole regions across a 4 × 4 × 4
  bin in one frame (1.04 measured, `dissolve_patterns.mov`). A candidate fix is a second test
  that a cut differs from the frame two before as well (d2(i) ≥ T), which rejects the return
  frame; a dissolve needs a spatial signal. Needs a new decision amending CJ-24 and a re-run of
  CJ-S4.
- "A dev hold on a package save, so a proof can publish a cache file during one" — CJ2a's
  `write-outside-publish` mutant survived `analysis_proof.py` A5 because a save takes about
  13 ms, even with a 1 GiB file in `cache/` (the analysis store is now proved by the probe row
  P9 instead); every other writer that goes through `CacheLedger.publish` (markers, waveforms,
  ramp audio) is unproved over MCP against a write during a save for the same reason. A dev-only `-RCDevSaveHold <s>` in
  `ProjectDocument+CacheSaves.swift` between `saveBegan` and `super.save` would let A5 publish
  inside a held save; it needs its own decision.

**Review.** First review: one should-fix, `write-outside-publish` surviving A5, fixed in
`0928e42d` by the probe row P9 above; two nits. Second review: verdict pass, every Files and
Approach item done, the SKIPPED Release re-runs after the fix justified (no app source or A-row
instrument changed). Three nits left as they are: a run evicted from `AnalysisLane`'s 256-run
order while still queued or running keeps its `runs` entry outside the limit
(`AnalysisLane.swift:235`); `analysis_job`'s `wait` treats an evicted run as not ended, so a dev
owner past 256 wants waits its whole deadline (`AgentServer+AnalysisJob.swift:106`); P9's
captured `failure` var would draw a Swift 6 strict-concurrency warning.

**Integration.** Cherry-picked (`bf767308…0928e42d`) onto `worktree-creator-jobs` after CU0a and
CJ5a, as one commit. Conflicts, each kept both sides: `11-decisions/creator-jobs.md` holds
CU-1…CU-9, "The phases' decisions" with CJ-50, then CJ2a's line and CJ-20…CJ-27; the file row's
summary names CJ-20…CJ-27 beside CJ-50, its Lines cell 465, the spec README's `11-decisions/`
total 17205, its §7.9e row CJ2a's text (§7.10 kept at CU0a's and CJ5a's 134);
`op_argument_proof.py` keeps CJ5a's `OPS = 65` and `OPS_WITHOUT_TOOLS` with `PRODUCT_TOOLS =
107`, and CJ5a's re-pin of the opaque-door count to 16, the same fix this phase made. TX1 has not
landed, so `creatorTools()` has one group. The CLAUDE.md edits owed above applied as written.
`make gate` on the integrated tree: names, typecheck (the four baseline warnings), test (199
result lines, 1991 passed, 0 failed) and app (D25, D26 ok) pass, fmt and lint skipped, "gate:
PASS 290s". Against its Release app: `analysis_proof.py` 22/22 (P1–P9, A1–A12, Z1 on all three
launches); on one instance from `proof_app.py launch --app release`, `op_argument_proof.py`
182/182 and `op_catalog_proof.py` 23/23, and `grep "Frame Job: "` on its log printed nothing;
`recording_probe.py --only catalog` 31/31. The two To-file drafts above were filed as issues at
integration (`ai-drafted`, `low-priority`).

**Owed.** S-TH1 (CJ-S4's no-cut input, a re-run when it exists) and S-TH4 (CJ-S3 (a), (c) on
the owner's 4K HLG). No manual checks.

### TX1 — the timeline's words

Bet 1 opens here. Every TX phase is in lane A, after CJ1. No TX phase changes the persisted format.
TX-70 was recorded at CJ0a; this bet writes no key sentence of its own.

- **What a person gets:** nothing in the window yet. An agent gets `get_timeline_transcript`: every
  heard word of the edited container in timeline order, nested instances included, each with its
  clip, track, editability and a stable identity, read on this Mac once per media and kept; clips
  with no words listed with why.
- **Head:** TX-S1 runs and its verdict is recorded; then TX-10…TX-14.
- **Decisions (draft):**
  - **TX-10 — The timeline transcript reads the words of every heard instance of a media clip in the
    edited container, nested ones included, in timeline order.** The instances are the plan's audio
    segments (one flattening walk, the core's). The plan gains `path` (the instance's
    `Instance::path`, enclosing nest clip ids outermost first, then the clip's) and `origin` (the
    project time of the inner clip's first frame) on a NESTED audio segment only, as `track_pans` is
    written only when needed, so every plan without a nest is the text it was (the plan is not
    persisted). An instance is read when its inner clip passes `Transcriber.jobs`' gate (on its own
    `ClipSnapshot`) and the plan's envelope over the segment is not zero throughout (Remove
    Silences' `audible`, so mute, solo, volume 0 and the same on an enclosing nest's track drop its
    words). The edited container is the open nest when one is open. Words come by TR-11's order —
    the cloud transcript when its marker serves `.captions`, else this Mac's (TX-12) — placed by
    R6-10's mapping (through S for a ramp), a nested word moved by the segment's `origin` less the
    inner clip's start and kept only inside the segment's span. **Order:** project start, end, track
    (front first; a nested word's enclosing nest clip's track), source order. **Identity:** (nest
    path, media id, source start tick, k), k counting earlier shown words with the same path, media
    and tick (0 unless one source plays twice); the inner clip's id is left out because a ripple
    gives every split's second half a fresh id. A clip the gate refuses is a row with the gate's
    sentence and no words ("clip 12 in nest Intro"). **The same speech twice:** two heard clips of
    different media overlapping for at least 5 s with matching words (TR-8-normalised tokens, a
    longest common subsequence ≥ 0.6 of the shorter side) are named in a note, "Clips 3 and 7 carry
    the same speech. Mute one, or switch its audio off, to read it once." Nothing is hidden.
  - **TX-11 — A word is shown but not editable when cutting it would break something**, in this
    order: inside a nest ("Inside nest <name>: open it (⌘↓) to cut its words."); under a transition
    ("Under a transition: a cut here would leave one clip's tail under its neighbour."); on a locked
    track ("Track <name> is locked: a cut would leave these words in place and move everything after
    them."). A ramped clip's words are editable (SR-18 (e)).
  - **TX-12 — The fill reads each heard media once, whole, on this Mac, and keeps it in TR-14's
    cache (amends TR-14).** It runs only when the Transcript tab shows or a tool needs words, never
    at import. It reads each heard media with no cloud transcript serving `.captions` and no stored
    run covering the whole file as ONE run from tick 0 to the end (a cache hit needs one stored run
    containing the asked span and runs never merge, so any growth of a played span would re-read
    it). Owners: the tab while it shows and each tool call while it waits; a Stop withdraws only its
    caller's want; an unwanted fill is cancelled through its `Transcriber.CancelToken`; one fill per
    document. One media at a time, off main, the media under the playhead first, then timeline
    order, through `SpeechEngine.transcribe` and `DeviceTranscriptCache.store`. Its priority is
    `.userInitiated` unless TX-S1's playback rule says `.utility` or a pause (then TX1 pays the
    `SpeechEngine.swift` toll first). The language is the Mac's unless chosen (a separate cache
    file). Outcome B (per-clip windows) if TX-S1 says so. TR-14's line: "**Amended by TX-12:** the
    Transcript tab, `get_timeline_transcript` and `review_transcript` also read this cache, and the
    tab's fill stores one run per media over the whole file. Captions, Remove Filler Words,
    `detect_fillers` and `transcribe_for_fillers` still never read it (TR-7)."
  - **TX-13 — `get_timeline_transcript {from?, to?, tracks?, language?}`**, an app-state read: off
    main, Stop reaches it, never the network, no AI-7 row. `words[]` carry `text`, `start`, `end`,
    `clip`, `track`, `media`, `engine`, `filler`, `speaker` when known, `editable` and `why`
    (`cut_start`/`cut_end` from TX3, `cuts[]` from TX5); `media[]` carries each heard media's
    `engine`, `language` and `fillers_reported`; `no_words[]`, `notes[]`, `count`, `project`.
    `from`/`to` are TR-13's window and refusals; an unknown track id is refused by name. The fill
    runs what the window needs as this call's want. Past 2,000 words the answer stops at a word
    boundary with `truncated: true` and `next_from`. `get_transcript` stays one clip (TR-11…TR-14).
  - **TX-14 — This bet applies CJ-3 through `ModelKeys` and adds no key rule of its own.** The
    transcript, cuts, restore, pauses and retakes need no key; filler strikes read any media whose
    AssemblyAI transcript serves `.fillers`, key or no key; Transcribe… (which uploads) is offered
    only with the key; the Fillers box is disabled only on CJ-12's condition; the hand-off is keyed
    as CJ-12's Assistant row.
- **Core:** `plan.rs`'s `audio_segment` writes `path` and `origin` on a nested voice only. New
  `core/tests/plan_instances.rs`: every existing fixture's plan without a nest is byte-identical to
  `d0661e5d`'s; a nest shown by two clips gives two segments with distinct `path`s and the right
  `origin`s; a nest in a nest gives a three-id path. No op, no format change.
- **FFI:** none.
- **Swift:** new and pure: `TimelineTranscript.swift` (the model, tokens, TX-10's order, heard rule
  and identity), `TimelineTranscript+Rules.swift` (nested placement, TX-11, the same speech twice);
  new: `TranscriptFill.swift` (owners, a serial queue off main, the `CancelToken`, progress,
  `DeviceTranscriptCache.store`), `AgentServer+TimelineTranscript.swift`,
  `AgentCatalog+Transcript.swift` (`AgentCatalog+Clips.swift` is 574). Changed:
  `CompositionPlan.swift` (`PlanSegment` decodes `path`, default the clip alone, and `origin`,
  leniently); `AgentServer+CreatorJobs.swift` (the row and the off-main name);
  `SilenceDetector.swift` (`isAudible` widened to internal); `DeviceTranscriptCache.swift` (its
  doc's reader list); `AssistantPrompt.swift` (`get_timeline_transcript` joins the captions topic's
  TOOL list; the guide stays 1,498 characters; `assistant_prompt_proof.py`'s digest re-pinned (`make
  test` checks it)); `SpeechEngine.swift` only on TX-S1's playback condition (its toll first, then a
  priority argument).
- **MCP mirror:** `get_timeline_transcript` (TX-13).
- **Docs:** `docs/guide/cleanup-tools.md` ("Reading a clip's transcript" gains the timeline read,
  paging and the fill's cost); spec: a new `07.9f-agent-transcript.md` with its README row, §7.2
  (the nested segment's keys), §5.6 (`device-transcripts`' readers, the whole-file run); §11
  TX-10…TX-14 and TR-14's line; `app/CLAUDE.md`, `core/CLAUDE.md` (`plan.rs`'s nested keys), root
  `CLAUDE.md`'s app-state tool list and product count.
- **Acceptance:** the read over each fixture equals the probe's expected tokens; a second read
  recognises nothing; Stop stores nothing; every plan without a nest is byte-identical.
- **Proof** (`timeline_transcript_probe.swift`, `timeline_transcript_proof.py`, Release): P1 two
  tracks and three media in TX-10's order, ties by track; P2 a muted clip's words absent, its
  unmuted twin's present; P3 a nest's words at the nest clip's start plus inner time, not editable
  with TX-11's sentence; P3b a nest shown by two clips: words twice, distinct identities; P3c a nest
  clip trimmed shorter than its nest: only the words it plays; P3d a duplicated clip: words twice, k
  0 then 1, and a selection of the second survives a ripple before both; P3e a nested clip with
  audio off under `no_words`, named with its nest; P4 a transition's words not editable; P5 a locked
  track's not editable; P6 a ramped clip's words equal `get_transcript`'s for it; P7 a reversed clip
  under `no_words` with the gate's sentence; P8 the same-speech note on a duplicated `say` track; P9
  an `assemblyai_fake` cache read first, `media[]` carrying `fillers_reported`; P10 one stored run
  per media covering the whole file; P11 a second call recognises nothing; P11b a clip trimmed 3 s
  outward, then a second clip of the same file placed: no recognition; P12 Stop answers "The
  transcription was cancelled." and stores nothing; P12b a tool call's Stop while the tab shows
  leaves the fill running; P13 paging at 2,000 words; G rows: each refusal's sentence.
  `transcript_proof.py` reruns as a regression (shared cache file).
- **Mutants** (8): the heard test dropped; the tie order by track reversed; the nest offset lost;
  `path` written on a top-level segment; k left out of the identity; the fill over the played span
  (P11b); a Stop cancelling every want; the page boundary off by one.
- **Manual checks:** none. **Depends on:** CJ0b, CJ0c (T8), CJ0a (T9). **Lane** A.
- **Questions for the owner:** (1) Two tracks carrying the same speech: show both and name the pair,
  or hide one? *Recommended: show both and name the pair* (hiding by a guess would hide a real
  second speaker). (2) Fill only when the tab shows or a tool asks, or also after import?
  *Recommended: only when asked.* (3) Read each media whole, or only its played span? *Recommended:
  whole* (TX-12).

#### TX1's record (2026-11-01)

**Landed.** Lane A, on the lane's branch from base `0210dfe7` (the lane's worktree was made at
`eb350b86` and fast-forwarded to the integration branch's head before any work). The owner's TX1
answers (2026-11-01): the same speech on two tracks — show both and name the pair; fill only when
asked — *yes*; read each media whole (minor, taken as recommended). TX-S1 ran at the head, then
TX-10…TX-14 were appended to `11-decisions/creator-jobs-2.md` with five index rows, and TR-14 got
its "Amended 2026-11-01, by TX-12" line, before the code. No op, no FFI, no format change, no UI. An
agent gets `get_timeline_transcript {from?, to?, tracks?, language?}`, the hundred-and-ninth
product tool.

**TX-S1** (`tools/proof/transcript_spike/fill_spike.py` and `fill_spike.swift`; `rule_sha256`
`5f784283c6a525aa8029942d0cf5aa91ac2b65d548576861d12ff1d25b2c043b`, matching CJ0a's table; OS
build 25F80, Apple M2 Max, 12 cores, 96 GiB, on AC, three lanes sharing the machine, load average
about 14 at the start). On `say` phrases joined into 16 kHz WAVs:
- 600 s: 7.30 s wall (0.40 s extract, 6.90 s recognition), 1,700 words, a 19,204,096-byte WAV,
  peak added `phys_footprint` 17,252,592 bytes.
- 3,600 s, twice: 40.74 s and 40.85 s wall (judged on the slower: 0.68 s per minute of speech;
  rule ≤ 360 s), 10,225 words each, a 115,204,096-byte WAV, peak added 16,220,400 and 16,253,168
  bytes (rule ≤ 1/32 of physical memory, 3,221,225,472). The figure is this process's footprint;
  the recogniser's own service process is not counted.
- Six 600 s windows of the 3,600 s file: 10,223 words, 10,119 matched to the whole run by spelling
  within 5 s, in order; median |Δ start| 0.00 s, p95 0.18 s, max 4.98 s (a common word matched one
  phrase over). A first matcher (`difflib`'s longest blocks) paired words a phrase cycle apart
  (median 113.9 s) and was replaced before the recorded run.
- `--playback` in the Release app: `play_preview` over 10 s of the 1080p H.264 timeline composed
  288, 300, 300 frames idle (median 300); 299, 300, 300 while a sibling process recognised the
  3,600 s file at default QoS (median 300, 100 % of idle); and the same under `taskpolicy -c
  utility` (100 %). The fill did not exist yet: this is a sibling process's reading.
- S-TH1 and S-LONG1 do not exist: skipped by name, **owed**.
- **Verdict: outcome A** (one whole-file run per media) and **`.userInitiated`**, so
  `SpeechEngine.swift` paid no toll and takes no priority argument.

**What changed.**
- Core: `plan.rs`'s `audio_segment` writes `path` and `origin` after `automation` when the voice
  has more than one stage. New `core/tests/plan_instances.rs` (7 tests): the SHA-256 of eight
  non-nest plans (plain, a speed ramp, `track_pans`, `automation`, `ducks`, `output` hlg, a
  transition, a muted track) printed at the base before `plan.rs` changed and pinned; no top-level
  segment carries either key; a nest shown by two clips gives paths `[3, 6]` and `[7, 6]` with
  origins at 4 s and 11 s; a nest clip shorter than its nest cuts the segment and keeps the origin;
  a nest in a nest gives `[3, 6, 9]`; the keys follow `automation` and no video segment has them.
  The spec's "a nest clip that cuts its head" case does not exist (a nest source has no `in`), so
  that test is the trimmed-tail case.
- Swift, new (`wc -l`): `TimelineTranscript.swift` 309, `TimelineTranscript+Rules.swift` 116,
  `TranscriptFill.swift` 248, `AgentServer+TimelineTranscript.swift` 270,
  `AgentCatalog+Transcript.swift` 72. Changed: `CompositionPlan.swift` (`PlanSegment.path`,
  `origin`), `AgentServer+CreatorJobs.swift` (the row, the off-main name, `transcriptTools()`),
  `SilenceDetector.swift` (`isAudible` internal), `DeviceTranscriptCache.swift` (its reader list;
  `currentStamp` internal), `TranscriptReader.swift` 238 → 241 (the corrected reader line;
  `recognize`'s defaulted `progress:`), `AssistantPrompt.swift` (`get_timeline_transcript` in the
  captions topic; the topic words unchanged). Not touched: `SpeechEngine.swift`,
  `ProjectDocument.swift`, `AgentServer.swift`.
- Instruments: `timeline_transcript_probe.swift` (T1–T11) and `timeline_transcript_proof.py` (G0,
  G1, P1–P13 with P3b–P3e, P10, P11b, C1; eight mutants); `PRODUCT_TOOLS = 109`;
  `get_timeline_transcript` in `APP_STATE_TOOLS` of `phase9_proof.py`, `recording_proof.py` and
  `recording_probe.py`.
- Documents: spec `07.9f-agent-transcript.md` (new) and its README row; §7.2 (the nested keys),
  §5.6 (`device-transcripts`' readers and the whole-file run), §7.4 (a row); the §11 file
  `creator-jobs-2.md` (252 → 370) with five index rows, `cut-by-transcript.md` (TR-14's line) and
  their Lines cells; `docs/guide/cleanup-tools.md` ("### Reading the whole timeline", and the
  measured rate in place of "a few seconds per minute"); `docs/guide/mcp.md` (a row);
  `tools/proof/README.md`'s TX1 section.

**Commands and results** (three lanes shared the machine; load average 72 at the end).
- `cd core && cargo test --release --test plan_instances`: printed the eight digests at the base;
  after `plan.rs`, 7/7. The nest suites (`nest`, `ramp_nest`, `matte_nest`, `dissolve_nest`,
  `track_mix`, `audio_automation`, `scope`) 115 tests passed. `cargo clippy --all-targets -- -D
  warnings` exit 0; `cargo fmt --check` after `cargo fmt`, exit 0.
- `make typecheck`: exit 0, the four baseline warnings, tsc silent.
- `python3 tools/proof/swift_build.py typecheck tools/proof/timeline_transcript_probe.swift`: exit 0.
- `assistant_prompt_proof.py --probe`: 14/14 (F4 "14 topics, 102 tools + 4 core against 106";
  F6 the guide 1498/1500).
- `spec_index_proof.py`: stale Lines cells fixed, then 228/228.
- Probe rows on the tree: first T3 and T4 failed because the probe linked the staticlib copied from
  the integration worktree (`cargo test` had not rebuilt it); after `cargo build --release`, 11/11.
- Debug (`make app-debug`): first 14/19 — P1's setup trimmed a clip past its file's end ("Trim End
  made no change"), an instrument fix; then P1, P10, P11, P11b, P2 5/5, and P12 1/1.
- `make gate`: names, typecheck, fmt, lint, test and app `pass` (1 s, 13 s, 6 s, 5 s, 266 s, 159 s),
  "gate: PASS 452s". After this record was written, again: names `pass`, the rest skipped,
  "gate: PASS 1s".
- `RC_PROOF_APP=release python3 tools/proof/timeline_transcript_proof.py`: 33/33 (T0–T11, G0, G1,
  P1–P13 with P3b–P3e, P10, P11b, C1). P1: 46 words from three media; P13: pages of 2,000 and
  1,839 over 3,838 words; P12: Stop on a 3,625 s WAV, "The transcription was cancelled.", nothing
  stored.
- `RC_PROOF_APP=release python3 tools/proof/transcript_proof.py`: 23/23 (`get_transcript`
  unchanged on the shared cache).
- On one instance from `proof_app.py launch --app release`: `grep "Frame Job: "` printed nothing;
  `op_argument_proof.py` 184/184; `op_catalog_proof.py` 23/23. `recording_probe.py --only
  catalog`: 31/31.
- Mutants (`timeline_transcript_proof.py --mutants`, Release, once on the final instrument):
  **eight of eight caught** — `no-heard` T2, `track-tie` T1, `no-nest-offset` T3 and T4, `no-k` T5,
  `stop-all` T11 (owner a answered cancelled, nothing stored), `page-off-by-one` T10 (1,999 words),
  `path-top-level` C1 (a CoW copy of `core/`), `played-span` P10 and P11b (a Release tree copy
  built in 152 s; runs shorter than their files, and a file rewritten after the outward trim).

**Deviations.**
- **The base.** The harness made the lane's worktree at `eb350b86`, three commits behind the
  integration branch; it was fast-forwarded to `0210dfe7` (CJ1 and CJ2b) before any work, so the
  range applies to the integration head.
- **`TranscriptFill.Item` carries the media record** (`record`), which the spec's interface did not
  list: the stamp is re-read after the run through `DeviceTranscriptCache.currentStamp`, which
  takes a `MediaSnapshot`. `init(key:)` is internal so the probe drives the fill without a
  document; the app makes one through `fill(for:)`.
- **The items are made off main, after the hop.** The hop reads the document, plan, snapshot,
  arguments, instances, `no_words` and each media's cloud transcript; the language, each media's
  stamp and the whole-file lookup follow `checkSpelling` and `transcriptionLanguage` off main,
  since the cache file is keyed by the language. `transcriptionLanguage` is asked only when a media
  in the window has no cloud transcript.
- **A fill whose file changed during the run, or whose store fails, refuses** the call with its
  own sentence ("… changed while it was being transcribed. Call again." / "… could not be kept in
  the project's cache."); TX-13 names only the recogniser's failure and a cancel.
- **TX-11's lock sentence names the track as stored**, so a default track reads "Track Track 1 is
  locked: …" — the road map's "Track <name>" taken literally.
- **P12b is a probe row (T11)**, not an app row: the Transcript tab (TX2a) does not exist, and two
  MCP calls do not run at once through the agent lane, so the second owner is driven directly on
  `TranscriptFill`.

**Fix pass 1 (review finding 1).** A run cancelled by one owner's release and wanted by another
before it unwound recorded `.cancelled`, so the second owner was refused "The transcription was
cancelled." without having stopped anything. `TranscriptFill`'s completion now leaves no outcome
when the token was cancelled and the item is wanted again, and the reconcile starts a fresh run.
T11 gained the case (over an empty `cache-rewant/`: d's run under way by `progress()`, d releases,
e wants, e answered `.stored` with one stored run), and a ninth mutant, `cancel-sticks` (the
completion records the outcome as before), fails it. Run: the probe rows T0–T11 12/12; `--mutant
cancel-sticks` caught (e answered cancelled, 0 runs stored); `--mutant stop-all` caught again. `make
gate`: names, typecheck, test and app `pass` (fmt and lint skipped, no Rust changed), "gate: PASS
419s".

**Reviews.** The first review (range `0210dfe7..a48a3f87`): one should-fix (the re-want race,
fixed in fix pass 1 above) and three nits. The second (`0210dfe7..b68d8008`): pass, with three
nits. The guide's "playback carried on at full frame rate while it ran" claimed the fill, which
TX-S1 never measured; corrected at integration to a separate process's read. "Track Track 1 is
locked" is the owner's wording call (Deviations). A run that ends `.failed` after its token was
cancelled and the item re-wanted keeps the failure for the second owner: rare, accepted as is.
`plan_instances`' "after `automation`" check finds the first `"path"` in the whole text (weak,
not wrong): accepted.

**Integration (2026-11-01).** Cherry-picked onto the integration branch after CU3a1 (format 38;
this phase has no format change). Conflicts only in shared indexes, each resolved keeping both:
`11-decisions/creator-jobs-2.md` (CU3a1's CU-30…CU-39 block, then TX-10…TX-14; 422 lines), its
README row and Lines cell, `designs/spec/README.md` (07.2 315, 07.3 497, 07.4 86, the 07.9f
row, 07.10 136, §11 17,670 in 36 files; `spec_index_proof.py` 228/228) and
`tools/proof/README.md` (CU3a1's section, then TX1's). The `CLAUDE.md` edits owed went in: the
root's app-state tool list and "one hundred and nine product tools", `app/CLAUDE.md`'s map entry
for the five new files, `PlanSegment.path`/`origin`, `DeviceTranscriptCache`'s readers and the
gate's count, and `core/CLAUDE.md`'s `plan.rs` nested keys.

**Owed.** TX-S1 on S-TH1 and S-LONG1 when they exist. The CJ-5 baseline cuts T1 and T2 are the
owner's (they were due when TX1 started). `07.9e` took no edit (499 lines). The lock sentence's
wording ("Track Track 1") is the owner's to settle.

### CU0b — the spikes

- **What a person gets:** nothing in the app; four verdicts.
- **Runs:** CU-S1…CU-S4 (rules in CJ0's list), each VERDICT line and `rule_sha256` recorded here
  before CU1a starts.
- **Manual checks:** the spikes' person rows, once, by the owner: real clicks and keys, A5's hover
  rows, A9's hidden cursors.
- **Depends on:** CU0a. **Lane** B. **Questions:** a STOP verdict (clicks, keys, mappings) is put to
  the owner before CU1a with the recommendation its rule names (CU-S1: positions only, or CU6 and
  CU8 filed; CU-S2: the burned cursor for windows, or the cursor file as data without a drawn
  cursor; CU-S5, later: zoom blur filed, cursor blur kept). A11's verdict names the grant's calls
  CU-3 uses, recorded before CU1a.
- **Acceptance:** each VERDICT line and `rule_sha256` recorded; `make gate` (nothing in
  `app/Sources` changes).

#### CU0b's record (2026-11-01)

**Landed.** Lane B, base `b2eccc35`. The instruments `tools/proof/cursor_spike/` (the runner
`cursor_spike.py`, the pure `deciders.py`, the probe `cursor_spike_probe.swift` with
`cursor_spike_capture.swift`, the scratch crate `reader/`, and its README), JOB-29, and this
record. Nothing in `app/`, `core/`, `graphic/`, `mcp-proxy/` or `agent/` changed. No new decision
ID: the CU0 block is full, and the phase sets no rule beyond the verdicts.

**The host.** macOS 26.5.1 (25F80), Apple M2 Max, on AC power (`pmset` first: "Now drawing from
'AC Power'"), two displays (the built-in panel, main, at 2×; a BenQ GW2790QT at 1×). Two other
lanes were running: the one-minute load average was 6.69 at the first CU-S4 run and 28.8 at the
second. The terminal held Screen Recording and nothing else:
`CGPreflightPostEventAccess`, `CGPreflightListenEventAccess` and `AXIsProcessTrusted` all false.
**The console was locked** (`CGSSessionScreenIsLocked`) for every run. The first CU-S2 and CU-S3
runs, made before the runner checked for that, recorded the lock screen: its animated Aerial
wallpaper, with no window and no menu bar (two frames read back with `ffmpeg`), every complete
frame's dirty rect the whole 3456 × 2234 display (CU-S3: 946 complete frames, no idle one).
Covering the display with the instrument and turning off its distractors changed nothing, since
the lock screen covered both. Those runs are void. The runner now reads the lock state in its
`host` mode and skips, by name, every row that needs the screen or an active window.

**Rule hashes (R0).** Each run recomputed CJ-7's hash of its entry, and each matched CJ0a's
record: CU-S1 `9508e82d119466262ed5fa48b7b3a6502b12022fa65b63ac0a35badfee23886c`, CU-S2
`15d61ec5374d3465b7f8a2f7c652ed6d78b099d0c2c5642946d8c87b3919c851`, CU-S3
`9ffadf0b9897880826cdddc0820ddc93bb0a2337bdf27e73b51c6fa41372ea5c`, CU-S4
`0fe71118ada7d67c52790943eb6cd5cf0c8b160377df3a72df207d54db47e208`. Each `results.json`
(`tools/proof/work/cursor_spike/cu-sN/`) stores its value.

**The verdicts.**

- **CU-S4** — `VERDICT body=json smoothing=whole-file json_mb=10.42 parse_ms=13.9 state_us=0.42
  prepare_ms=2.7`. The worst case (432,000 moves, 7,200 click records for 3,600 clicks, 20,000 key
  marks, 40 images of 4,096 bytes, 3,600 image changes, one geometry entry, LCG seed 1) is a
  10,421,911-byte JSON body or an 11,097,407-byte binary body. The release profile ran five runs
  of each measure, twice; both runs gave the same verdict. Run 2 (the line above): JSON parse and
  validate [14.377, 13.414, 13.539, 13.938, 13.890] ms; binary [1.261, 0.422, 0.393, 0.396,
  0.411] ms; `prepare` at smoothing 1 [2.702, 2.684, 2.631, 2.653, 2.680] ms over the JSON body
  and [2.802, 2.695, 2.629, 2.626, 2.616] ms over the binary body. The median `state at t` was
  0.416 µs (JSON) and 0.375 µs (binary) prepared, and 0.416 and 0.334 µs raw. Run 1 printed
  `parse_ms=13.6 state_us=0.42 prepare_ms=2.6`: JSON parse [14.254, 13.648, 13.713, 13.545,
  13.392] ms, binary [1.048, 0.454, 0.399, 0.400, 0.389] ms. R4a passed both times: the two
  bodies parsed to equal tracks, with 0 mismatches over 200 state requests (100 seeded times,
  unprepared and prepared). Each state is a JSON request string to a JSON answer string.
- **CU-S3** — `VERDICT dirty=owed bursts_within=0/10`. All ten bursts were skipped by name (the
  console locked). The "0/10" counts measured bursts within 64 pt, and none was measured.
- **CU-S2** — `VERDICT mapping_display=owed mapping_window=owed separate=owed anchor=owed
  e1_still_p95_ms=owed`. Every source row and the ten still starts were skipped (the console
  locked), and the picked window's two rows are a person's.
- **CU-S1** — `VERDICT positions=owed clicks=owed keys=owed cursor_image=owed hidden=owed
  image_fallback=owed event_clock=owed secure=owed relaunch=owed grant_api=owed listed=owed`.
  Measured rows:
  - A4: `CGEvent(source: nil)?.location` cost 0.083 µs median per call over 10,000 calls (p95
    0.125 µs, max 17,110 µs, no nil). All 10 `CGWarpMouseCursorPosition` warps were seen, measured
    with the console locked and recorded with that fact.
  - A5's safe thread: `NSCursor.currentSystem` answered from a background queue 10 times without
    a crash or a nil.

  Skipped by name:
  - A4's real moves, A5, A9's TextEdit rows, A8 and A11 need a person (`--person`).
  - A1–A3, A6 and A7 need input posted, and the terminal cannot post
    (`CGPreflightPostEventAccess` false). The runner skipped them under the lock first. They are
    owed to the person tier's real input in the scratch bundle.
  - A5's own cursors, A9's helper and A10 need an unlocked console.

**What each verdict feeds.**

- CU-S4 settles CU-10's body and smoothing for CU1a: a JSON body, columnar, with integer µs and
  points × 100, version 1; smoothing prepared over the whole file. The numbers are tens of times
  inside every bound, so the shared machine's noise cannot move the verdict.
- CU-S1 feeds CU-3's pair (`grant_api`, `relaunch`, `listed`) and CU-11 (the capture sources
  and rates: positions, clicks, keys, the image sampler, hidden spans).
- CU-S2 feeds CU-20 (the mapping), CU-12 (the anchor) and CU3c's default (`separate`).
- CU-S3 feeds CU-72 (typing's aim) and CU9b.
- All three are owed. They are put to the owner before CU1b and CU6. They are not STOPs.

**Owed (JOB-29).** At the unlocked machine, the owner runs `python3
tools/proof/cursor_spike/cursor_spike.py --only s1,s2,s3`, then `--person`. A11 answered nothing,
so CU-3 gains no "Settled at CU0b" line yet.

**Instrument rows.**

- The selftest: 16/16. The ten mutants (`rule-unchecked`, `clicks-95`, `keys-accessibility-ok`,
  `grant-iohid-first`, `skipped-as-measured`, `inherited-grant-counted`, `caret-unflipped`,
  `odd-window-ignored`, `dirty-128`, `body-or`) each exited 1.
- The reader: `cargo fmt --check` and `cargo clippy --release --offline -- -D warnings` clean.
- B0 builds through `swift_build.build` (optimized) and signs the scratch bundle `Cursor
  Spike.app` (`com.kgalligan.FrameJob.cursorspike`, flags `adhoc,runtime`).
- `spec_index_proof.py` 222/222.
- The gate: `make gate` once, after the instruments and the documents, before this line was
  written: "gate: PASS 493s". The steps were names 0.6 s, typecheck 7.4 s, fmt 3.1 s, lint
  25.1 s, test 293.5 s and app 162.7 s (`build/gate/times.tsv`). `name_residue.py` was re-run
  over the record, exit 0.

**Deviations.**

- `CGCursorIsVisible()` is unavailable to Swift in the macOS 26.2 SDK, not deprecated with a
  warning as the CU header expected. The probe reaches it through `dlsym` for the record.
- The probe gates only In the picture rows on being active. Separate's marker needs no
  activation.
- The runner skips screen rows when the console is locked. That case is not in the spec, and the
  void runs above show why.
- The S3 mode gained three diagnostic job flags (`distractors`, `color_space`, `cover`), which
  the rule's run never sets.
- `keys` uses the same ≥ 99 % per-window delivery as `clicks`, because the rule names no figure
  for keys.
- `relaunch=not-needed` when the chosen pair's tap, made after the grant in the running process,
  delivers keys.
- With no candidate passing, `event_clock` answers `none`.
- MB is 10^6 bytes.

**Review and fix pass.** The first review found a blocker and two should-fixes, all in the
person and posted tiers; fix 1 (`8ea44d42`, on `66bf29e2`) changed only `cursor_spike.py`,
`cursor_spike_probe.swift` and the README:

- The posted tier's listener was opened after the input was posted. `listen_row` now opens the
  scratch bundle first, then runs the poster, then waits for the answer. The bundle answers
  `ready_wall` once its tap or monitors exist, and a row whose `ready_wall` is missing or not
  before the poster's start is an instrument failure. A poster's `skipped` skips the row.
- A7 was measured under whatever grant the bundle held. It now runs only under
  `input-monitoring` or `both`, and is otherwise skipped as `scratch bundle holds <grant>`.
- A8/A11's count windows raced the person. Grant mode now counts both taps side by side, each in
  its own slot, over one 8 s window that opens at the later of the grant's detection and a go
  file the runner writes on the owner's Return (bounded at 150 s). A11 fails when `go_seen` is
  false.

Fix 1's runs: `--build-only` exit 0, no warning; `--selftest` 16/16; `--only s1` exit 0, the
pinned hash, every field `owed`; a direct run of the reordered row skipped by the poster's reason
with `ready_wall` 4.571 s before `start_wall`; `make gate` "gate: PASS 313s". The mutants and
s2–s4 were not re-run, since fix 1 touched none of their code. The second review passed with two
nits: a reader `cargo test` figure no run printed (dropped from this record), and A11's prompt
not naming where to type, so keys typed into the terminal would pre-answer the next prompt. At
integration `ask()` flushes a terminal's pending input before each prompt and the prompt names
TextEdit; `--selftest` 16/16 after.

**Integration.** Cherry-picked onto `worktree-creator-jobs` after CJ5a and CJ2a. Three conflicts,
each kept both sides: the decisions index's `creator-jobs.md` row keeps the CJ-20…CJ-27 and CJ-50
summary, its Lines cell 465 → 471, and the spec README's `11-decisions/` total 17205 → 17211 in 35
files; `tools/proof/README.md` holds CJ2a's section and then this one. `spec_index_proof.py`
222/222. No `CLAUDE.md` edit and no issue owed.

### CJ2b — the Analyzing sheet and Split at Shot Changes

- **What a person gets:** Clip ▸ Split at Shot Changes on a flattened video (a finished edit, a
  downloaded clip, a stream VOD): the Analyzing sheet while the cuts are found, with Stop, then one
  undo step that splits the clip at every hard cut.
- **Decisions (draft):**
  - **CJ-28 — One Analyzing sheet for every kind whose result a command plans with.** A command
    whose analysis is not cached shows "Analyzing" and its name, each media's progress, and Stop,
    which withdraws the command's wants and lands nothing. A tool call shows no sheet and waits. The
    words follow the menu's American verbs ("Analyzing", "Analyze"). (CO-6 amends this for a
    render-substituted kind, which shows no sheet.)
  - **CJ-29 — Clip ▸ Split at Shot Changes and `split_at_shots {clips?}`.** The selected media clips
    (none selected: the item validates off) are split at each cut inside their played window, mapped
    to clip time through the source map, on the canvas grid, as one undo step "Split at Shot
    Changes". A cut within one frame of a clip's edge is dropped. Locked tracks and linked partners
    follow `split`'s rules (AU-92). Over the clip ceiling the whole command is refused before any
    split, naming how many clips it would add — each split counted with every linked partner it also
    cuts — and how many fit.
- **Core, FFI:** none (a composite of `split`, CJ-8 (f)).
- **Swift:** `AnalyzingSheetController.swift`; `EditorViewController+ShotSplit.swift` (the command,
  its validator arm, the planner mapping source cuts to clip time through `SourceMap` and
  `ReverseMirror`); the Clip row in `clipMenu()` (`AppDelegate+Menus.swift`, :251–395 at
  `d0661e5d`; `AppDelegate+ClipMenus.swift` holds only the Clip menu's submenu builders);
  `UIMenuTable.swift` and `inventory.json` rows.
- **MCP mirror:** `split_at_shots {clips?}` in `AgentServer+Analysis.swift`, naming Clip ▸ Split at
  Shot Changes, a `creatorHandlers` row and off-main.
- **Docs:** `docs/guide/editing.md`, `menus-and-shortcuts.md`, `mcp.md`; spec §9, §7.9e; a screen
  for the sheet (`designs/screens/15f-analyzing-sheet.md`); the counts for one
  product tool; `docs/manual-checks.md` (JOB-2).
- **Acceptance:** `make gate`; `shot_split_proof.py` PASS against Release; the screen captured.
- **Proof rows:** S1 the fixture placed whole splits into one clip per shot, each starting on its
  cut frame, as one undo step; S2 a trimmed, ×2 and reversed placement splits only at the cuts
  inside its played window, each at its mapped time; S3 a cut within one frame of an edge is
  dropped; S4 a split past the ceiling is refused before anything changes, naming both counts, on a
  clip with a linked partner; S5 under `-RCDevAnalysisHold 3`, Stop (`cancel_sheet`) lands nothing
  and leaves no marker.
- **Mutants** (5): the edge rule removed (S3); the mirror skipped (S2); the ceiling checked after
  the first split (S4); partners left out of the count (S4); Stop leaving the want (S5).
- **Manual check:** **JOB-2** — on a finished video of your own with hard cuts and a dissolve, Split
  at Shot Changes cuts at every hard cut and nowhere inside a shot; the sheet reads as progress and
  Stop is immediate.
- **Depends on:** CJ2a, CJ0c (T5). **Lane** C.
- **Question for the owner:** ship Split at Shot Changes as the lane's first door? *Recommended:
  yes* — it serves VR's flattened clips, is useful alone (Final Cut Pro 12.3's Edit Detection), and
  proves the lane end to end.

#### CJ2b's record (2026-11-01)

**Landed.** Lane C, on the lane's branch, from base `eb350b86`: `8fbdef73` and the review's fix
`5bd9e7ab`, landed on the integration branch as one commit. The owner's answer
(2026-11-01): Split at Shot Changes is the analysis lane's first door — *yes*. Decisions CJ-28 (the
Analyzing sheet) and CJ-29 (Clip ▸ Split at Shot Changes and `split_at_shots`) were recorded in
`11-decisions/creator-jobs-2.md` before the code, renumbered from the draft's CJ-27 and CJ-28
because CJ2a took CJ-27 (`analysis_job`); the screen is `15f-analyzing-sheet.md`, before
`16-recorder-panel.md`, which must run last. No core, FFI or format change (CJ-8 (f)). A person
gets Clip ▸ Split at Shot Changes (no key) and the Analyzing sheet; an agent gets `split_at_shots
{clips?}`.

- **New files** (`wc -l`): `ShotSplit.swift` 201 (the planner both doors call),
  `AnalyzingSheetController.swift` 178 (193 after the fix), `EditorViewController+ShotSplit.swift`
  112. Wiring and growth: `AnalysisLane.swift` 297 → 320 (`progress(of:)`, a running job's
  share read, stored under the lane's lock with no broadcast and cleared when its run ends),
  `AnalysisShots.swift` 218 → 227 (`run`'s defaulted `progress`), `AgentServer+Analysis.swift` 268 → 373
  (`splitAtShots`, `waitForShots`), `AgentCatalog+Analysis.swift` 66 → 103,
  `AgentServer+CreatorJobs.swift` 53 → 56, `AppDelegate+Menus.swift` 471 → 475,
  `EditorViewController.swift` 1,079 → 1,080 (the validator line, frozen), `UIMenuTable.swift`
  131 → 132, `AssistantPrompt.swift` (`split_at_shots` in the "cut and time" topic, no words).
  Not touched: `AgentServer.swift`, `ProjectDocument.swift`.
- **Instruments:** `shot_split_proof.py` (S1–S8, S4n, Z1, eight mutants);
  `analysis_fixtures.py`'s `shots_sound.mov`; `PRODUCT_TOOLS = 108`; `split_at_shots` in
  `APP_STATE_TOOLS` of `phase9_proof.py`, `recording_proof.py` and `recording_probe.py`;
  `inventory.json`'s `splitAtShotChanges:` row and its `presentAsSheet` site; `screens.py`'s
  `ANALYSIS_HOLD` (`-RCDevAnalysisHold 600` on every launch, counted pinned by P2) and
  `RCDevAnalysisCanned` in `NOT_SHOWN`.
- **Documents:** spec §7.4 (83 → 84), §7.9e (482 → 498), §9 (228 → 232) and their index cells;
  the §11 file `creator-jobs-2.md` (59 → 109) with two index rows; `docs/guide/editing.md`
  (### Split at Shot Changes), `menus-and-shortcuts.md` (two rows), `mcp.md` (a row, and the
  open-nest list); `docs/manual-checks.md` JOB-2; `tools/proof/README.md`'s CJ2b section.

**Commands and results** (host on AC power; three lanes shared it, load average 75 at the end).
- `make typecheck`: exit 0, the four baseline warnings, tsc silent.
- `python3 tools/proof/swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS
  tools/proof/analysis_probe.swift`: exit 0 (the probe compiles unchanged).
- `analysis_proof.py --only P1,…,P9`: 9/9. `capture_spike/inventory.py --check`: 5/5.
  `v2_menu.py --only H`: 5 pass of 5. `assistant_prompt_proof.py --probe`: 14/14, F4 "14 topics,
  101 tools + 4 core against 105". `spec_index_proof.py`: first four Lines cells stale, then
  225/225.
- Debug, `make app-debug` then `shot_split_proof.py --only S1,S2,S3,S8`: 5/5; `--only
  S4,S4n,S5,S6,S7`: first 4/6 — S4's filler track was looked up among two tracks (there is no
  third until one is added) and S4n compared clip counts read inside the nest's scope (where
  `get_project` answers the scoped view); both instrument fixes, then `--only S4,S4n` 3/3.
- `make gate`: names, typecheck, test and app `pass` (fmt and lint skipped, no Rust input
  changed), "gate: PASS 593s". After the `phase9_proof.py` fix, the screen's prose and this
  record, again: names and test `pass`, the rest skipped, "gate: PASS 88s".
- `RC_PROOF_APP=release python3 tools/proof/shot_split_proof.py`: 10/10 (S1–S8, S4n, Z1 on both
  launches); S6's split landed 5.1 s after the press, S7's sheet went after 5.47 s.
- `RC_PROOF_APP=release python3 tools/proof/analysis_proof.py`: 22/22.
- On one instance from `proof_app.py launch --app release`: `op_argument_proof.py` 183/183;
  `phase9_proof.py` 246/247 — the `detach_audio` row (below), then, after the instrument fix, on a
  second instance 247/247; `recording_proof.py --no-screen --no-microphone` 142/142 (79 skipped
  by name); `grep "Frame Job: "` on both logs printed nothing. `recording_probe.py --only
  catalog`: 31/31.
- `RC_PROOF_APP=release python3 tools/proof/screens.py --only 15f-analyzing-sheet`: 6 pass of 6,
  the sheet captured light and dark, "Waiting" visible.
- Mutants (`shot_split_proof.py --mutant <name>`, once each on the final instrument): **eight of
  eight caught** — on Debug tree copies `edge-rule-removed` S3 (60 and 240 split),
  `mirror-skipped` S2 (the reversed clip's starts 1260…1440 for 1340…1520), `windows-hulled` S8
  (coverage [[0, 312]]), `ceiling-after-first-split` S4, `partners-uncounted` S4 and
  `ceiling-counts-scope` S4n (each answered the core's "too many clips: 4097 (max 4096)" in
  place of the composite's sentence); on Release tree copies `stop-keeps-want` S5 (the marker
  written 3.0 s after Stop) and `stale-test-removed` S7 (the split landed after the marker).

**Deviations.**
- **The planner is `ShotSplit.swift`**, not the editor extension the draft named, because the
  tool calls it too (SY-1's shape); the editor file is the door, its stale test and its arm.
- **The two held-row mutants ran on Release tree copies.** On a Debug copy the first analysis job
  of a fresh launch, under three lanes' load, outlasted the rows' bounds: `stop-keeps-want`
  SURVIVED (no marker within S5's 10 s) and `stale-test-removed` failed S7 only because the sheet
  had not gone within 30 s (S7 alone on the Debug app took 25.47 s). On Release the job lands
  about 2 s after the 3 s hold, and both were caught for their own reasons. The bounds are the
  spec's and unchanged; the recorded run is Release's.
- **A failed `split` past the ceiling is the core's error, not a partial edit:** the ceiling
  mutants answered "too many clips: 4097 (max 4096)" with nothing applied, so S4 and S4n catch
  them by the sentence (and S4n by its count) rather than by a partial split.
- **The menu's no-cut press beeps**; the tool answers `added: 0` with a note and no undo step.

**Files outside the spec's list.** `tools/proof/phase9_proof.py`'s `content()` now strips
`linked` beside `id` and `track` (the file is in the list for `APP_STATE_TOOLS`): its
`detach_audio` row compared a detached pair's `linked` ids, which differ between the two paths
it compares (`content()` predates the field, format 28), so the row failed on code this phase
does not touch; with the id stripped as its docstring says ("everything that names an id"),
247/247.

**Review.** Review 1: fix-required, one should-fix — AppKit runs `viewDidDisappear` and
`viewDidAppear` when the window is ordered out and back (a minimize), so the release cancelled
the job and the `didStart` guard left the restored sheet frozen at its last percentage, Stop its
only way out. Fixed in `5bd9e7ab`: a `viewDidDisappear` with no outcome and no Stop clears
`didStart` and sets `reappearing`, and the next `viewDidAppear` wants every row not yet landed
again and restarts the poll; `viewDidDisappear` stays the one release, and `stop-keeps-want`'s
anchor line is unchanged. The fix pass: `make typecheck` exit 0 (four baseline warnings, tsc
silent); `make gate` "PASS 453s"; `RC_PROOF_APP=release python3 tools/proof/shot_split_proof.py`
10/10; `screens.py --only 15f-analyzing-sheet` (Release) 6 pass of 6; the mutants not re-run (no
anchor line touched). Review 2: pass, one nit — no row, mutant or person check exercised the
minimize path; resolved at integration by JOB-2's step 5 (minimize while the sheet shows a
percentage, restore, the split lands).

**Integration.** Conflicts only in the indexes and the decision file, where CJ1 and CU2 had
landed first: `creator-jobs-2.md` keeps CJ-28 and CJ-29 after CJ1's CJ-10…CJ-13 (252 lines), its
row in `11-decisions/README.md` gains CJ2b's clause, and the spec index's cells are §7.4 84,
§7.9e 499, §9 238 and `11-decisions/` "17487 in 36 files"; `spec_index_proof.py` 225/225. On
the merged tree with the CLAUDE.md edits and this record, `make gate`: names, typecheck, test and
app `pass` (fmt and lint skipped), "gate: PASS 274s".

**CLAUDE.md edits** (applied at integration):
- Root `CLAUDE.md`: "for all one hundred and seven product tools" → "for all one hundred and
  eight product tools"; in "Verifying a build"'s app-state list, "`get_transcript`,
  `get_media_analysis`," → "`get_transcript`, `get_media_analysis`, `split_at_shots`,".
- `app/CLAUDE.md`, "The document.", the analysis bullet: its file list gains "·
  `ShotSplit.swift` · `AnalyzingSheetController.swift` · `EditorViewController+ShotSplit.swift`"
  after `AgentServer+AnalysisJob.swift`, its citation "spec §11 CJ-20…CJ-27" becomes "spec §11
  CJ-20…CJ-29", "`get_media_analysis` (`AgentServer+Analysis.swift`, off main) waits" becomes
  "`get_media_analysis` and `split_at_shots` (`AgentServer+Analysis.swift`, off main) wait", and
  at its end: "Clip ▸ Split at Shot Changes (road map creator-jobs CJ2b, CJ-28, CJ-29):
  `ShotSplit` is the planner both doors call — targets, one request per media over the union of
  the played windows, cuts mapped to the canvas grid with the edge rule, the ceiling counted with
  partners on the unscoped project before any op, one `split` per cut latest first;
  `AnalyzingSheetController` the generic Analyzing sheet (a row per missed media polled from
  `AnalysisLane.progress(of:)` and `run(of:)`, Stop only dismisses, its one owner released in
  `viewDidDisappear`); `EditorViewController+ShotSplit` the menu door, its stale test and
  `validateShotSplitAction`."

**To file:** none.

**Owed.** JOB-2 (the owner's finished video, at the machine, steps 1–5).

### TX2a — the Transcript tab

- **What a person gets:** View ▸ Transcript (⌃⌘T) shows a fifth inspector tab: the timeline's words
  in paragraphs, each led by its timecode. While the video plays the spoken word is highlighted and
  the view follows it; a click on a word moves the playhead there. Words that cannot be cut are dim
  with the reason on hover; clips with no words are listed with why. Space, J, K and L still play.
- **Head:** TX-S2 runs and its verdict is recorded; then TX-20…TX-23 (TX-22's bar half is TX2b's).
- **Toll first:** `EditorViewController+Inspector.swift` (403, over its 400) gives up `// MARK: -
  Commands the inspector made real` (142–370) to `EditorViewController+InspectorCommands.swift`, a
  pure move gated alone, with its history entry.
- **Decisions (draft):**
  - **TX-20 — The Transcript is the inspector's fifth tab: Clip, Media, Document, Transcript,
    Assistant. View ▸ Transcript (⌃⌘T) shows it. Amends AI-4 and AI-14.** The pane is
    `AssistantPane`'s shape (one view, built once, scrolling itself); the menu item is in
    `AppDelegate+ViewMenu.swift` beside View ▸ Assistant. AI-4's line: "the strip has five tabs; the
    Assistant is fifth, after Transcript." AI-14's line: "the Transcript tab is kept like the
    Assistant tab on a selection change that is not a click; a click on a clip also leaves it
    showing and scrolls the transcript to that clip's first word" — the click clause only if the
    owner says yes below. Risk accepted: the transcript gets the inspector's 280–440 pt, and showing
    it hides the Clip tab.
  - **TX-21 — The transcript view is not an `NSText`, so the editor's bare keys still reach
    `handleEditorKey`.** As first responder it takes ← and → (by word, seeking), ↑ ↓ (by line), ⇧
    with any of these (extend), ⌘A, Esc (clear), ⌫ and ⌦ (cut, TX-31), Return (restore, TX-51);
    every other key goes up the chain, so Space, J, K, L, I, O and M behave as on the timeline.
    Arrows deviate on purpose (words here, frames on the timeline).
  - **TX-22 — The view.** The highlight is the latest word whose start is at or before the playhead
    (lit through the pause after it). While playing the view keeps it in sight unless the person
    scrolled within the last 3 s. A click puts the playhead at the word's start, playback continuing
    if it was playing. A paragraph breaks on a pause of 1.5 s or more (voice cache), a change of
    speaker label or of track, led by its timecode, which also seeks. (TX2b: Words from, a
    per-window track filter, and Language, a popup of installed recognition languages, both view
    state, not saved.) The view rebuilds on a new project handle while it shows, never during a live
    gesture, keeping the scroll anchored on a word's identity.
  - **TX-23 — `transcript_view` is a dev tool** (Debug and Release, never Distribution), on main
    like `select_inspector_tab`. It answers the shown tokens, the highlighted word, the selection,
    the strikes kept, the fill's progress and owners, and each keyed control's enabled state and
    tooltip; it can set the selection, focus the view and press the tab's buttons.
- **Core, FFI:** none.
- **Swift:** new `TranscriptPane.swift` (subclassing the pane base; `InspectorPane.swift`
  unchanged), `TranscriptView.swift` with `+Layout`, `+Keys` and `+Highlight` (TX-S2's view),
  `EditorViewController+Transcript.swift` (the command and validator arm, seek, the follow hook),
  `AgentServer+TranscriptView.swift`. Changed: `InspectorTab.swift` (a `transcript` case before
  `assistant`, which moves the Assistant tab's raw value, the strip index, from 3 to 4: every reader
  of an index is re-checked, and the unmerged tutorials branch's targets are the integrator's,
  Risks); `InspectorViewController.swift` (frozen: one arm in `pane(for:)`, and a guard in
  `clipPicked()` if the owner says yes); `EditorViewController+Inspector.swift` (after its toll,
  `inspectorPlayheadMoved()` forwards to the pane); `AppDelegate+ViewMenu.swift`;
  `UIMenuTable.swift` and `inventory.json`; `AgentServer+DevTools.swift` (the dev row, on main);
  `EditorWindow.swift`'s `SpaceKey.route` and `space_key_probe.swift` if the view takes first
  responder. Pins: `v3_tools.py`'s `TABS` (:52) gains `transcript` before `assistant`;
  `dev_tools.py`'s count gains one.
- **MCP mirror:** none for the tab (view state); `select_inspector_tab` reaches it by title; the dev
  tool `transcript_view`.
- **Docs:** `docs/guide/transcript.md` (new) and its `docs/guide/README.md` row; the README
  highlight; `menus-and-shortcuts.md`; spec: a new `04.3e-inspector-transcript-tab.md` with its
  README row, §9, §7.9c (the dev tool); §11 TX-20…TX-23 with AI-4's and AI-14's lines;
  `app/CLAUDE.md`; root `CLAUDE.md`'s dev tool list; `docs/manual-checks.md` (JOB-10).
- **Acceptance:** the tab shows TX1's model exactly; highlight and seek follow TX-22; the transport
  keys reach the editor; TX-S2's numbers hold in the harness on the fixture.
- **Proof** (`transcript_tab_proof.py`, Release, and harness probes): T1 (probe) the five titles fit
  at the 280 pt minimum by `PanelTabsView.tabRect`'s arithmetic against each title's width, and
  `snapshot_ui` at the default width reads them from the dump; T2 `transcript_view`'s tokens equal
  `get_timeline_transcript`'s words; T3 after `play_preview` the highlighted word is TX-22's for the
  reported playhead; T4 a click on word *i* puts the playhead at its start; T5 (harness) Space, J
  and L sent to the focused view reach `handleEditorKey`, and ← moves one word; T6 a rebuild after
  an MCP `split` under 100 ms on the S2 fixture; T7 (harness) no rebuild during a live trim.
- **Mutants** (5): the highlight by containment; the 3 s follow pause ignored; Space consumed by the
  view; the paragraph pause at 1.0 s; a rebuild during a live gesture.
- **Manual check:** **JOB-10** — reading and following a long transcript while S-TH1 plays: the
  highlight keeps time with the voice and the scrolling is calm.
- **Depends on:** TX1; TX-S2 at its head. **Lane** A.
- **Questions for the owner:** (1) The view as a fifth inspector tab, a panel beside the preview, or
  its own window? *Recommended: the tab* (the pane machinery, `select_inspector_tab` and
  `snapshot_ui` reach it; no new split in the frozen editor; a later window would be a second host).
  (2) The title if "Transcript" does not fit five tabs at 280 pt? *Recommended: "Transcript" if T1
  passes, else "Words".* (3) A click on a timeline clip while the transcript shows: stay and scroll,
  or switch to Clip? *Recommended: stay.* (4) View ▸ Transcript on ⌃⌘T? *Recommended: yes* (pairs
  with ⌃⌘A; checked for a clash). (5) Find in the transcript (⌘F) now or later? *Recommended: later,
  filed, unless TX-S2's view gets `NSTextFinder` for free.*

#### TX2a's record (2026-11-01)

**Landed.** Lane A, on the lane's branch from base `118ebe9a` (the lane's worktree was made at
`eb350b86`, before TX1; it was reset to the integration branch's head `118ebe9a` before any
work). The owner's TX2a answers (2026-11-01): the host is the fifth inspector tab; a timeline click
while the transcript shows stays and scrolls; the title "Transcript" if T1 passes, else "Words";
⌃⌘T; ⌘F later (the last three minor, taken as recommended). The toll was committed alone first
(`ab28f128`); then TX-S2 ran; then TX-20…TX-23 were appended to `11-decisions/creator-jobs-2.md`
(moved to `creator-jobs-3.md` at integration, below) with four index rows, and AI-4, AI-14 and
AI-19 got their "Amended 2026-11-01, by TX-20" lines,
before the tab's code. No core, FFI, op or format change. A person gets View ▸ Transcript ⌃⌘T and
the inspector's fifth tab; an agent gets nothing new (the tab is view state), a proof the dev tool
`transcript_view`.

**The toll.** `EditorViewController+Inspector.swift` 403 → 175 (`wc -l`): lines 142–370 at
`118ebe9a` (`// MARK: - Commands the inspector made real` through the blank line before `//
MARK: - Validation`) moved whole into `EditorViewController+InspectorCommands.swift` (237), a
pure move, nothing widened; `inventory.json`'s `presentNoFootageForTransition` site and its two
citations and `tools/proof/README.md`'s row re-pointed to `:157`. `make typecheck` (the four
baseline warnings), `inventory.py --check` 5/5, `make gate` "gate: PASS 411s"; committed alone.
TX2a's own `inspectorPlayheadMoved()` line then made it 176.

**TX-S2** (`tools/proof/transcript_spike/view_spike.py` and `view_spike.swift`; `rule_sha256`
`543a30274c8dc99a2404daee513faeefc6248c912cc078036d74c24dad40c09a`, matching CJ0a's table; OS build
25F80, macOS 26.5.1, Apple M2 Max, 12 cores, 96 GiB, on AC, three lanes sharing the machine).
Candidate (b), `TranscriptView`, built `-O` over `app/Sources`, in a 304 × 800 pt scroll view in an
offscreen window, over 27,000 synthetic words in 900 paragraphs on two tracks (40 collapsed, 300
struck, 10 % not editable); medians of 20.
- The head's recorded run (load average 21.05 30.45 28.38): first layout and draw 10.7 ms (rule ≤
  200), a rebuild with one word removed 24.9 ms with the anchor kept (≤ 100), a highlight to the
  adjacent word 0.036 ms and to one 5,000 words away 0.037 ms (≤ 2), `tokenIndex(at:)` 0.0047 ms
  (≤ 1), a three-paragraph selection drawn 0.17 ms, 30,736,408 bytes of added `phys_footprint` (≤
  1/256 of physical memory, 402,653,184); not an `NSText`; `SpaceKey.route` `.transport` with the
  view first responder; J, K and L reached a sink past the view. **Verdict: (b)**; (c) and (a) not
  built.
- Before it: the first two runs met every bound but drew no text (`view.png` held only the
  selection): TextKit 2 draws a dynamic colour (`labelColor`) into a `CGContext` as nothing
  (a stand-alone check drew 0 dark pixels with `labelColor` and 3,767 with black), so the view
  resolves its colours in its appearance. A third run, under load average 44.70, missed the
  rebuild bound by 31.8 % (131.8 ms; the near-miss rule's re-run did not apply): one attributed
  string per word, replaced by one string styled by ranges; the run after it read 25.4 ms. A
  fourth showed the selection drawn over unlaid text: `draw` now walks the fragments from the
  dirty top. Each run was a 58–60 s build and well under a minute of measuring.
- On the final tree (T11, load average 52.32 34.30 31.83): first layout 10.9 ms, rebuild 24.7 ms,
  highlight 0.033 and 0.033 ms, hit-test 0.0047 ms, selection 0.16 ms, 31,096,880 bytes; verdict (b).

**What changed.**
- Swift, new (`wc -l`, after the fix passes): `TranscriptTokens.swift` 164,
  `TranscriptTabSource.swift` 399, `TranscriptPane.swift` 215, `TranscriptView.swift` 356,
  `TranscriptView+Layout.swift` 160,
  `TranscriptView+Highlight.swift` 82, `TranscriptView+Keys.swift` 103,
  `TimelineTranscript+Document.swift` 110, `EditorViewController+Transcript.swift` 26,
  `AgentServer+TranscriptView.swift` 183. Changed: `InspectorTab.swift` (`transcript` before
  `assistant`), `InspectorViewController.swift` 359 → 363 (frozen: the `pane(for:)` arm, the
  `clipPicked()` line, the head doc), `InspectorTabBadge.swift` (the raised dot), `AssistantPane.swift`
  (its doc), `EditorViewController+Inspector.swift` (the playhead forward),
  `AgentServer+TimelineTranscript.swift` 270 → 223 (the factored read; `wordRow` internal),
  `AppDelegate+ViewMenu.swift`, `UIMenuTable.swift`, `AgentServer+DevTools.swift` 120 → 123, and
  `FillerWords.swift` (below). Not touched: `EditorViewController.swift`, `EditorWindow.swift`,
  `TranscriptFill.swift`, `ProjectDocument*.swift`, `AgentServer.swift`, `Controls.swift`, core.
- Instruments: `transcript_tab_probe.swift` (T1, T3p, T4p, T5, T7–T10) and `transcript_tab_proof.py`
  (Z0, M1, T2–T4, T6, T11, T12; seven mutants); `assistant_tab_probe.swift`'s P14 (e) accepts the
  raised dot; `v3_tools.py`'s `TABS`; `dev_tools.py`'s `DEV_TOOLS`; `inventory.json`'s
  `showTranscript:`; `timeline_transcript_proof.py`'s `played-span` anchor (the line it edited moved
  into the factored read).
- Documents: spec `04.3e-inspector-transcript-tab.md` (new) and its README row, the lettered-files
  sentence and the Lines cells; §4.3a, §3, §7.9b, §7.9c (`transcript_view`), §9 (⌃⌘T, the View list,
  the view's keys), §7.4 (a row); §11 TX-20…TX-23 (`creator-jobs-2.md` 422 → 519 on the lane,
  `creator-jobs-3.md` 146 → 243 at integration) and `assistant.md` (225 → 233) with their index
  rows and cells; `docs/guide/transcript.md` (new, page 10), the guide index
  renumbered, the README highlight, `menus-and-shortcuts.md`, `assistant.md`, `timeline.md`;
  `docs/developing.md`; `docs/manual-checks.md` (JOB-10; AS-9's Expect); `tools/proof/README.md`'s
  TX2a section.

**Commands and results** (three lanes shared the machine; load averages 21 to 59).
- `make typecheck`: exit 0 after each Swift change, the four baseline warnings, tsc silent.
- `python3 tools/proof/swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS
  tools/proof/transcript_tab_probe.swift`: exit 0.
- `inventory.py --check` 5/5; `v2_menu.py --only H` 5/5; `spec_index_proof.py` 231/231.
- Probe rows in the loop: first 8/9 — T10's view kept the width it was made with plus the clip
  view's growth (584 pt in a 304 pt clip view), fixed in `TranscriptView` (it follows its clip
  view's width); then two fixture fixes (longer words, T10 before T7's trim); then 9/9.
- Debug (`make app-debug`): first 4/7 (two arguments spelled wrong in the instrument:
  `set_playhead`'s `t`, `split`'s `clips`); then T2, T3, T12 passed and T6 failed at a median
  311 ms over five splits.
- `make gate`: first FAIL at test (`assistant_lane_proof.py` L3, "B frontmost false", a window
  ordering on the shared machine, nothing this phase touches); re-run "gate: PASS 278s" (test 110 s,
  app 167 s).
- `RC_PROOF_APP=release python3 tools/proof/transcript_tab_proof.py`: 15/17. M1 read the re-shown
  tab before it had read its words again (an instrument wait, fixed: `wait: 30`); T6's median was
  223.8 ms. A bench over the app's own read (`-O`, 27,000 words in six clips of one media) put
  `TimelineTranscript.words` at 200 ms, 185 of them in `FillerWords.isFiller`, which built its
  `CharacterSet` union on every call; made once, `words` read 13 ms and the whole rebuild about
  30 ms. On Debug the median fell to 123 ms.
- `make gate` again: "gate: PASS 293s" (names 1 s, typecheck 7 s, test 147 s, app 136 s). After
  the documents were finished, again: names `pass`, the rest skipped, "gate: PASS 1s".
- `RC_PROOF_APP=release python3 tools/proof/transcript_tab_proof.py`: **17/17** (T0, T1, T3p,
  T4p, T5, T7–T10, Z0, M1, T2–T4, T6, T12, T11). T2: 57 tokens equal to `get_timeline_transcript`'s
  57 words, every key and id, and one `no_words` row; T6: 27,000 tokens in 900 paragraphs, rebuilds
  after five splits 22.0, 22.1, 22.8, 21.3, 21.8 ms (median 22.0); T12: A's 21 tokens shown while
  the 3,625 s WAV's run stood at 0.052, the hidden tab refused, and shown again the fill read none
  (the run was cancelled).
- `python3 tools/proof/transcript_tab_proof.py --mutants` (Release, once on the final
  instrument): **seven of seven caught** — `highlight-containment` T3p (nil in the gap),
  `follow-pause-ignored` T8 (scrolled 8,745 pt one second after the person's scroll),
  `space-consumed` T5 (J and L rates 0), `paragraph-1.0s` T9 (a break after the 1.2 s gap),
  `live-rebuild` T7 (3 rebuilds during the trim), `clip-picked-switches` T10 (the tab switched),
  `one-wait` T12 (a Release tree copy; A's tokens never shown while the long WAV read).
- `RC_PROOF_APP=release python3 tools/proof/timeline_transcript_proof.py`: 33/33 (the tool's
  factored read; P13 pages of 2,000 and 1,839 over 3,838 words).
- `RC_PROOF_APP=release python3 tools/proof/assistant_tab_proof.py`: 26/26; P14 (e) at 280 pt: the
  dot raised at (272, 1) above the title's top 7.5, at 480 pt right of the title.
- `python3 tools/proof/v3_tools.py --app release` took `release` as a bundle path and exited 1
  before any row; `RC_PROOF_APP=release python3 tools/proof/v3_tools.py`: 8/8 (`TABS` with
  `transcript`; the dev-tool block ends `transcript_view`).
- `python3 tools/proof/proof_app.py launch --app release`: `grep "Frame Job: "` on its log printed
  nothing; the instance was stopped by its pid.

**Deviations.**
- **The base.** The worktree was made at `eb350b86`, before TX1, which this phase depends on; it
  was reset to the integration head `118ebe9a`, whose counts matched the spec's.
- **The view was written before the decisions**: TX-S2 measures `TranscriptView` itself, so the
  view and `TranscriptTokens` came first, the decisions after the verdict, the rest after them.
- **`FillerWords.swift` is outside the spec's files**: its `normalized` made the trimmed set once
  (a pure speed-up, the same set); without it T6 failed at 224 ms on Release.
- **`timeline_transcript_proof.py`'s `played-span` anchor moved** with the factored read: the
  mutant now appends the item with the played length at the tool's `items.append(item)`.
- **T4's playing half is the probe's T4p**: no MCP door starts playback, so the app row checks the
  playhead and that a paused transport stays paused, and T4p clicks a word while playing.
- **T12 reads the release by the run's restart**, not `owns_want` false: `transcript_view`
  refuses a hidden tab (TX-23), so the row checks the refusal, then shows the tab again and reads
  the fill — none running, so the long run was cancelled.
- **T1 reads the titles by `PanelTabsView.tabRect`'s arithmetic only**: `Controls.swift` is not
  forked, so the dump half of the road map's T1 is dropped.
- **`TranscriptPane.source` is `TranscriptTabSource!`** set after `super.init`, since its
  `onChange` closure needs the pane; `TranscriptTabSource.init` takes `ProjectDocument?`.
- **`transcript_view` also answers `status_text`**, the status line's sentences.
- **`space-consumed`** swallows every key the view does not take (Space never reaches the view:
  `SpaceKey.route` takes it at the window), so J and L never reach the editor.

**Fix pass 1 (`136d6451`, review 1's blocker and should-fix).** (1) `show(_:)` left the ⇧ anchor
an old index, so ⇧→, an edit that shrank the tokens, ⇧-arrow and any rebuild trapped on
`model.tokens[$0.upperBound]`; the anchor is now remapped by its word's `Identity` (else the
selection's lower bound, nil with no selection) and clamped in `move(to:extend:)`. New probe row
T13p: ⇧← again 1...3; cut to 3 words, ⇧→ 0...0, anchor 0; rebuilt. Its control (the remap removed)
scored 1/2. (2) `setShown(false)` left `waiting` set, so a show before the waiter woke dropped
that media from `pending` as still running and never wanted it again; it now clears `waiting`
under the lock, and T12 polls until the long media is read anew after a hide and after a hide and
show at once. Run: probe rows 10/10; `make gate` "gate: PASS 442s"; Release
`transcript_tab_proof.py` **18/18** (T6 median 22.64 ms; T12 shown again `{'media': 3,
'fraction': 0.0029}`, hidden and shown at once from 0.0151 `{'fraction': 0.0038, 'media': 3}`);
the launch grep printed nothing. The mutants, TX1's, the Assistant's and v3's proofs were not
re-run: no anchor line or file they cover changed.

**Fix pass 2 (`69c54bdb`, review 2's should-fix).** The pass-1 comment had taken
`TranscriptTabSource.swift` to 401, over the new-file 400; folded to one trailing comment, 399. No
code changed. `make typecheck` the four baseline warnings; `make gate` "gate: PASS 401s".

**Reviews.** Review 1 (`118ebe9a..54ec9698`): one blocker and one should-fix (fix pass 1) and
three nits. Review 2 (`118ebe9a..136d6451`): one should-fix (fix pass 2) and three nits. Review 3
(`118ebe9a..69c54bdb`): pass, with three nits carried. Two were done at integration:
`inventory.json`'s `setTransitionKind:` note re-pointed from `(:282)` to `(:157)`, and the §7.9c
row's summary in `designs/spec/README.md` names `transcript_view`. The third, T12's quick hide and
show making two MCP round trips (so it catches the race only when the timing lines up, with no
control run recorded), is accepted as is.

**Integration (2026-11-01).** Cherry-picked onto the integration branch after CO0 and CU3a2
(no format change in this phase). Conflicts only in shared indexes, each resolved keeping both:
`11-decisions/creator-jobs-2.md` kept CU3a2's CU-33 and CU-37 at 475 lines, and TX-20…TX-23 went
to the end of `creator-jobs-3.md` (146 → 243) instead, since `creator-jobs-2.md` had passed the
series' ~500-line rule at CO0 and would have read 572; their four index rows follow CO-1…CO-9 and
name `creator-jobs-3.md`, whose Holds cell gained them; `creator-jobs.md`'s row kept CU3a2's 478;
`designs/spec/README.md`'s §11 cell 17,997 in 37 files (`spec_index_proof.py` 234/234). The
`CLAUDE.md` edits owed went in: the root's dev tool list (`transcript_view`), and `app/CLAUDE.md`'s
`InspectorTab` entry (five tabs, the Assistant 4), the `InspectorViewController` entry (the
`clipPicked()` guard and the `.transcript` arm), the raised dot, `+InspectorCommands`, and one
entry for the tab's ten new files. `make gate` on the merged tree: names, typecheck, test and app
`pass` (fmt and lint skipped, no Rust changed), "gate: PASS 293s".

**Owed.** JOB-10 (a person, with S-TH1 once it exists). Find in the Transcript tab (⌘F) is filed
as an issue.

### CU1a — the cursor file and its read-back

- **What a person gets:** nothing visible. The format, the core's check and the writer exist, proved
  on synthetic segments.
- **Core:** `cursor_file.rs`, format v1 in CU-S4's body. Its module doc is the specification: a
  header (`format`, `version`, `in_picture`, the source kind, display id, the stream's point size
  and pixels per point, the content size, `movie_size`, the anchor `e2` or `e1` and its host time,
  `cursor_image` `current-system` or `none`); columnar `moves`; `images` (PNG, hot spot, point size,
  `kind` when it equals a known system cursor); `image_changes`; `hidden` spans when CU-S1 found a
  signal; `clicks` (button, down/up, position, click count); `scrolls`; `geometry` (CU-S2's fields,
  per change); `dirty` when CU-S3 passed; `keys` (`shortcut` entries: time, spelled keys in the
  Keyboard keys template's tokens with `+` spelled `plus`, the layout-independent key code; `typed`
  entries: time only), defined now and empty until CU6. All times are integer microseconds from the
  movie's first frame. The validator caps each array and refuses each failure in its own sentence; a
  `typed` entry with any field but its time is refused (CU-7). `ffi_cursor.rs`: `rc_cursor_open` and
  `rc_cursor_free`; `core/tests/cursor_file.rs`; both exports in the null-safety sweep.
- **FFI:** the two exports, their header entries, `ReelCursor`'s init and `deinit` in a new
  `ReelCore+Cursor.swift` (CU-9, CJ-8 (l)).
- **Swift:** `CursorCaptureBuffer.swift` (pure, probe-callable: fed samples, clicks, scrolls,
  images, geometry changes and key entries with host times; `openSegment`,
  `closeSegment(movieSize:)` answering the body; every array reset at each open);
  `CursorAnchor.choose(e2:e1:)` (E2 when present, else E1, named in the header);
  `CursorFileWriter.swift` (writes `.partial`, opens it through `ReelCursor` as the read-back,
  renames it into place; a failed open leaves no file and answers the core's sentence);
  `CursorValues.swift` (the typed header, `rc_*`-free).
- **MCP:** none.
- **Docs:** spec §7.1, §7.10; `core/CLAUDE.md` (`cursor_file.rs`, `ffi_cursor.rs`), `app/CLAUDE.md`
  (`ReelCursor`, the three files); `app/CLAUDE.md`'s `ReelCore+Cursor.swift` entry.
- **Decisions (draft):** **CU-10** format v1, owned by `cursor_file.rs`. **CU-14** a cursor file
  that fails to write or read back is that segment's `cursorProblem` and the landing's note, never
  the recording's failure. **CU-15** one file per segment movie, named by its stem. **CU-16** the
  header's two sizes: the content size for the mapping, `movie_size` for import's match.
- **Acceptance:** `cargo test --release --test cursor_file`; every synthetic segment the probe
  writes is accepted by the core; `make gate`.
- **Proof rows** (`cursor_capture_probe.py`, probes, no grant, Release): C1 two segments with a
  pause: each file only its own samples, times from its own first frame; C2 three geometry changes
  fed, three entries written; C3 E2 when given, E1 when not, named in the header; C4 the writer with
  a corrupted body leaves no file and answers the core's sentence; C5 every synthetic fixture
  round-trips with equal counts; C6 an odd content size (1001 × 701) with a 1002 × 702 movie: the
  header's `movie_size` is the movie's.
- **Mutants** (6): the buffer not reset at a segment's open (C1); geometry recorded once only (C2);
  E1 chosen when E2 exists (C3); the read-back skipped (C4); `movie_size` from the content size
  (C6); a `typed` entry with a label accepted (core test).
- **Depends on:** CU0b (CU-S4's body; CU-S3's `dirty`), CJ0d (T15). **Lane** B.

#### CU1a's record (2026-11-01)

**Landed.** Lane B, base `90465898` (I's HEAD with CU0b; the lane worktree was made at
`822973cd` and fast-forwarded to it before any edit). One decisions commit (`b4dfc3c0`: CU-10,
CU-14…CU-17 and their index rows), then one commit with the code, the probe and the documents
(`0b7b1c4f`), then fix 1 (`ca9276a7`); landed on `worktree-creator-jobs` as one commit. Nothing a
person or an agent sees changed: no tool, catalog, menu, recorder file or format version moved,
so the parity check is untouched. The recorder's wiring is CU1b's.

| File | Lines | What |
|---|---|---|
| `core/src/cursor_file.rs` | 367 | the module doc (format v1's specification: the keys, the columns, the caps, every sentence, the parse order), `RC_CURSOR_FILE_VERSION`, the caps, the types, `CursorFile::parse` |
| `core/src/cursor_file_check.rs` | 333 | `check`, `check_typed` (CU-7's `typed` rule, run in the loose read) and `decode_base64` |
| `core/src/ffi_cursor.rs` | 51 | `rc_cursor_open`, `rc_cursor_free` over `read_bytes`, `fallible_op`, `boxed`, `free_boxed` |
| `app/Sources/ReelCore+Cursor.swift` | 27 | `ReelCursor` (`init(data:)` through `withNonNullBytes` and `takeErrorMessage`, `deinit`) |
| `app/Sources/CursorValues.swift` | 193 | the typed header, `CursorFileBody`, `CursorAnchor`, `CursorFileProblem`; no `rc_*` |
| `app/Sources/CursorCaptureBuffer.swift` | 230 | the pure buffer, CU-17's rules |
| `app/Sources/CursorFileWriter.swift` | 52 | `.partial`, the read-back through `ReelCursor`, `rename(2)`; a failure removes both paths |
| `core/tests/cursor_file.rs` | 641 | 12 tests through the two exports |
| `tools/proof/cursor_capture_probe.swift` · `.py` | 370 · 177 | B0, C1–C6 and five mutants |

**Measured.**

- `cargo test --release --test cursor_file`: 12 passed. Pinned: a minimal and a full file
  accepted (negative scroll deltas, touching hidden spans, three images, both anchors and
  `none`), the full file's values read back through `CursorFile::parse` (the PNG bytes against
  an RFC 4648 encoder written in the test); every refusal sentence; each of the eleven caps at
  its count accepted and one past refused, and one PNG at 1,048,576 bytes accepted and one byte
  more refused; a v2 body with a key v1 does not know refused by its version naming 2 and 1; a
  project-shaped `{"format_version": 38, "tracks": []}` refused by the format sentence; touching
  hidden spans accepted, overlapping ones refused; the header's `RC_CURSOR_FILE_VERSION` equal
  to the const; NULL bytes "bytes is NULL".
- `cargo test --release --test model_tests null_safety`: 1 passed, with `rc_cursor_open` and
  `rc_cursor_free` in the sweep.
- `cargo fmt` and `make lint`: clean (one `type_complexity` in the test fixed with a `type
  Edit`).
- Core mutants, each run once and reverted byte-identical: `typed` accepting a `label` in
  `check_typed` — `a_typed_key_is_its_time_only` failed (11 passed, 1 failed); the version
  check moved after the strict read — `format_and_version_are_read_before_the_strict_parse`
  failed (11 passed, 1 failed).
- `make typecheck`: exit 0, 0 errors, the 4 baseline warnings.
- `python3 tools/proof/cursor_capture_probe.py`: "scores: 7/7" (B0 and C1–C6), exit 0, built
  in 30.6 s; the recorded run after the gate reused the build and printed "scores: 7/7".
  C4's three sentences: "the cursor file is version 2; this Frame Job reads cursor files up to
  version 1", "the cursor file is not JSON: EOF while parsing a string at line 1 column 377",
  "keys.typed holds a typed key's time only; \"label\" is refused (spec §11 CU-7)".
- The five Swift mutants, each exit 1 ("caught"): `buffer-not-reset` (C1: segment 2's moves
  `[0, 500000, 600000]`, 2 images), `geometry-once` (C2: 2 entries, not 4), `e1-over-e2` (C3),
  `readback-skipped` (C4: the writer kept all three and `.fjcursor` was left), and
  `movie-size-from-content` (C6: `[1001, 701]`).
- `spec_index_proof.py`: 222/222.
- The gate: `make gate` once, after the code and the documents and before this record was
  written (load average 7.85 at its start): "gate: PASS 388s" — names 1 s, typecheck 6 s, fmt
  3 s, lint 6 s, test 227 s, app 144 s. `name_residue.py` was re-run over the record.

**Deviations from the road map, as the spec recorded them.** `closeSegment` takes `anchor:`
beside `movieSize:`, since E2 has been answered or dropped by the close; `CursorSegmentStart`
carries the opening `geometry`, written at t 0, so every file has the one entry v1 requires.
The road map's sixth mutant (a `typed` label accepted) is the core's first mutant.

**Implementation choices the spec left open.**

- The strict read deserializes the loose `Value` (not the bytes), so a serde sentence carries
  its path and no "at line N column M": "the cursor file at \"source\": unknown variant
  `screen`, expected one of `display`, `window`, `picked`"; the root reads "the cursor file at
  its top level: missing field `moves`". Every column, the `keys` object and every header key
  but `display_id` and an image's `kind` are required.
- An image's base64 is decoded after the strict read and before the check, through a private
  `png_base64` field the read fills and the parse empties: "images[i].png is not base64: …"
  (a length not a multiple of 4, a byte outside the alphabet, `=` before the end, more than two
  `=`).
- The sizes' range (`content_size`, `movie_size` 1…16384) has its own sentence ("content_size
  [0, 10] is outside 1…16384"), as does `anchor_host_us` below 0, and a version below 1 ("the
  cursor file is version 0; versions start at 1"). A hot spot lies inside `[0, w] × [0, h]`.
- The buffer writes only what CU-17 lists; it adds no guard of its own (a non-PNG image, a
  click button past 31): what the core refuses there is that segment's `cursorProblem`
  (CU-14). It converts a value that is not finite to 0 rather than trap, and encodes a float
  that is not finite as a string the read-back refuses by name.

**Review and fix pass.** The first review found one should-fix: `decode_base64`'s "it ends in
more than two \"=\"" refusal was pinned by no test, though Approach step 2 and this record said
every sentence was. Fix 1 (`ca9276a7`) added `images[0].png = "iVBOR==="` to the refusal table
(`cursor_file` 12 passed; "gate: PASS 395s"); the probe, its Swift mutants and the core mutants
were not re-run, since no Swift, probe or mutant-anchor file changed. The second review passed,
carrying three nits: `cursor_file.rs`'s parse paragraph sent the check's sentences to
`cursor_file_check.rs`'s module doc, which points back (re-worded at integration to "under **The
check** below"); CU-10's loose read left out CU-7's `typed` keys, which the code reads before the
strict parse (added at integration); and every image's base64 is decoded before `check` applies
the 1,024-image cap (left: the sentence is the same either way and the bytes are already read).

**Integration.** Cherry-picked (`b4dfc3c0…ca9276a7`) onto `worktree-creator-jobs` at CU0b's
`90465898`, with no conflict. The decisions file had reached 519 lines, so by the series' rule
(spec §11 `creator-jobs.md`'s head) CU-10 and CU-14…CU-17 moved to a new
`11-decisions/creator-jobs-2.md`: `creator-jobs.md` is back to 471 lines, the index's five rows
link the new file, the new file has its row (59 lines), and the spec README's `11-decisions/`
total is 17276 in 36 files (`spec_index_proof.py` 225/225). The `CLAUDE.md` edits owed (the
`cursor_file.rs`, `cursor_file_check.rs` and `ffi_cursor.rs` entry in `core/CLAUDE.md`;
`ReelCore+Cursor.swift` in `app/CLAUDE.md`'s core's-edge bullet and the three `Cursor*.swift` files
under **Recording.**) applied as written. `make gate` on the integrated tree: "gate: PASS 361s"
(names 1 s, typecheck 7 s with the four baseline warnings, fmt 3 s, lint 10 s, test 207 s, app
133 s). Then, with `RC_PROOF_APP=release`, `cursor_capture_probe.py` built afresh from the
integrated `app/Sources` (30.0 s) and printed "scores: 7/7", C4's three sentences as above.

**Owed.** Nothing: no manual check, no owner step and nothing to file.

### CO0 — scope, the record, the tolls' schedule and the spikes

Bet 6 opens here. The cutout phases run in lane C on CJ2a's analysis lane; the layout phases (CO6
on) run in lane B after CU. Nothing in this bet needs a key: person segmentation is Vision on the
Mac and hide-while-silent reads Silero's spans; no CO control or tool is in `ModelKeys.keyed`.

- **What a person gets:** nothing visible; the CO record opened.
- **Decisions (CO-1…CO-9, recorded at CO0, now in `creator-jobs-3.md`):**
  - **CO-1 — Remove Background uses Vision on the Mac.** Video uses
    `VNGeneratePersonSegmentationRequest`, a FRESH request per frame, on the device CJ-S2's rule 1
    picks for it (CO1 re-runs rule 1), never `.fast` (stateful). Pictures may use
    `VNGenerateForegroundInstanceMaskRequest` (CO10); video never does (it flickers). This adopts
    #124's D5. A matting model, shipped or downloaded, is allowed by CJ-1 and not built here; it is
    filed as a candidate only if JOB-60's verdict asks for it, and Frame Job being Apache-2.0, a
    GPL-3.0 or AGPL model (Robust Video Matting, Concat's) cannot ship in it. CO-S1 (speed only,
    S-KEY1 owed): Standard is person `.balanced` at every frame, 1.81× realtime at 1080p30, its mask
    512 × 384; the numbers are in CO0's record.
  - **CO-2 — The cutout is a property of the clip's own layer, not a matte track.** `video.cutout`
    on a media or still clip. A luma matte track holding a rendered mask has no link to the camera
    clip, so a trim, split, slip, speed change, ramp or reverse would slide the outline off it
    (MT-2); a per-layer mask is fetched the way the picture is and follows every edit. Closed
    vocabulary; R5-1 and G-1 stand.
  - **CO-3 — The mask reaches the compositor from a per-media mask pack, looked up through the
    picture's own segment (rewritten at CO0: CO-S2 failed the mask track and kept the pack).** A
    cutout adds no composition track: the plan, the composition,
    `CompositionBuilder.firstExtraTrackID` and the eight-decoder warning are what they are without
    it. For each request, the compositor maps the composition time through the covering picture
    segment's linear map in ticks to the source time the picture shows there (a reversed clip's in
    the reversed stream it reads), takes the source frame shown at that time (the last at or before
    it, as AVFoundation holds a frame), and draws the mask of the NEAREST analysed source frame,
    ties to the earlier, in the stream the segment reads: exact at every-frame analysis, nearest at
    a capped rate. A reversed clip's analysed times are mirrored by `T − end`, `ReverseMirror`'s
    CMTime convention, never `T − pts`. The mask's bytes go from the pack to the compositor as
    stored and never pass AVFoundation's colour path. CO-S2's numbers are in CO0's record.
  - **CO-4 — Masks are an analysis kind on CJ2a's lane and store, one pack per media (rewritten at
    CO0 to CO-S2's pack).** Kinds `masks` (Standard) and `masks_best` (Best, only if CO-S1 keeps
    it). The store is CJ-22's: `cache/analysis/masks/<media id>.json` with the stamp (no path; the
    kind's version, the request digest and revision, rate, read size, OS build, device), and one
    payload file, the pack `cache/analysis/masks/<media id>/masks.pack`: a frame table (each source
    frame's time and the slot of its nearest analysed mask), an offset table (each distinct analysed
    mask's time, offset and length) and each distinct analysed mask once, 8-bit at Vision's own
    size, compressed with `NSData.compressed(using: .lzfse)`. The grid is CJ-23's analysed frames;
    CJ-22's coverage holds the analysed ranges, each run recording `subject_found`, and a publish
    rewrites the pack whole through CJ-22's `.partial` and rename. A reversed clip reads the same
    pack, mirrored at lookup (CO-3), never a second analysis and no mirrored file (D4-6). Masks are
    in DISPLAY orientation. `get_media_analysis {media, kind: "masks"}` answers runs (`from`, `to`,
    `subject_found`, frame count) and the stamp, never pixels. The package carries the folder.
    Clarifies CJ-22 (one payload file per media, in the media's folder); amends CJ5b's CJ-51
    (`cache/analysis/` copied whole, the packs included). Where CO-5 and CO-6 say "chunks", read the
    analysed ranges a run covers. The pack measured 62.32 MB a minute on CO-S1's masks (no rule; a
    risk in CO0's record).
  - **CO-5 — "No person found" is decided per clip window.** A clip whose analysed chunks found no
    subject (no mask with ≥ 0.5 % of its pixels above 127) draws uncut, its status "No person
    found"; once any chunk of its window finds one, every analysed frame honours its mask, so a
    person who walks out leaves an empty picture. Swift decides it from the runs' `subject_found`;
    the core never reads analysis (CJ-20).
  - **CO-6 — A frame without its mask draws uncut; a file waits (amends CJ-28).** Pending, cancelled
    and failed chunks draw the clip uncut, never blank and never the slate. An export waits for
    every chunk its range needs through `Exporter.withRampAudio` and fails with `cutoutFailed`
    naming the clip when one fails. `render_frame` and File ▸ Save Frame… wait up to 30 s for their
    one frame's chunks, then draw uncut and say so (`render_frame` in a sentence before its last;
    Save Frame in an informational sheet after saving). The eyedropper and the look gallery do not
    wait. A render-substituted kind shows no Analyzing sheet: the person keeps editing and the
    Background section says what is happening. A command that PLANS from masks (CO7's centroid)
    reads only what is cached.
  - **CO-7 — The analysis sees the picture as SDR; the mask is not a colour (amends CJ-23).** A
    converting media is read by `AVAssetReaderTrackOutput`, every frame's presentation time kept,
    and each frame converted through step 0's own pass (`InputPass`) on the GPU — not through the
    one-clip composition, whose frames lose the source's times. The mask is a coverage 0…1
    multiplied in at step 7 like the corner radius and the matte, the same in SDR, HLG and
    linear-light projects; it never passes step 0 (mask track ids never reach `InputStage`; a mask
    buffer is wrapped raw). CO-S2 chose no class for masks: the pack's masks never become a
    composition track, so they never pass AVFoundation or step 0, and a composition with a cutout
    is built with the class it would have without one; read "mask track ids" as the pack's bytes,
    uploaded as stored. Any edge refinement reads the picture as the chroma key reads it
    (`KeyReading`, HD-13 (h), HD-20).
  - **CO-8 — Where it is drawn.** The mask binds at `texture(4)` (CJ-8 (b)) on every layer,
    shadow-silhouette, reflection and matte draw, a 1×1 white placeholder when the layer has no
    cutout; sampled at the same DISPLAY-space coordinate as the picture (after the spotlight lens
    and the pixelate snap, before `orientedUV`). `LayerUniforms` gains one group of four (enabled,
    edge, feather, a spare): 132 → 136 floats, 528 → 544 bytes, if it lands first. In general the
    block is 132 + 4·g floats (528 + 16·g bytes) after g groups of four have landed, and CU3a2 adds
    several (the sprite rect, the ripples' positions and phases, their colour and size), counted at
    its own landing; the integrator re-pins the size proofs at each landing (CJ-8 (b)). The shadow
    and reflection follow the cut outline (MT-3).
  - **CO-9 — The spikes' rules are CJ0's**; CO-S4 is retired into CJ-S3 (b), which CO1 re-runs with
    a masks job.
- **Amendments recorded now:** CJ-22 (CO-4's clarification), CJ-23 (CO-7's third arm), CJ-28 (CO-6).
  CJ5b writes CJ-51 with the masks included (CO-4). Recorded in later phases: MT-1, MT-2, MT-4
  (CO5), R5-4, AU-110 (CO9), CAM-10 (3), CAM-10 (5), CAM-4, CAM-11 (CO8). Standing: R5-1, G-1,
  R5-4's mechanism, R5-5, D4-6, W-8, #367, CU-5, MT-9, the Concat rule and its extension to AGPL
  recorders.
- **Tolls CO pays** (each a pure move gated alone, by the first CO phase that must edit the file,
  unless another lane paid it): `edit_action.rs`'s end-patch door → `edit_action_end.rs` (CO2a1);
  `actions.rs` → `actions_json.rs` (CO2a1 or CO9, only if wiring would pass ~590); `evaluate.rs`'s
  `Segment` → `plan_segment.rs` lapsed for CO (CO-3's pack adds no `mask_of`, so CO2a1 no longer
  edits `evaluate.rs`; SW3a or SW2c pays it);
  `AgentCatalog+Properties.swift` → `AgentCatalog+VideoPatch.swift` (CO2a1); `Exporter.swift`'s
  offline single frame → `Exporter+Frame.swift` (CO2b); `EditorViewController+SaveFrame.swift`'s
  options → `SaveFrameOptions.swift` (CO2b); `format_history.rs` → `format_history_early.rs` (the CO
  bump whose paragraph would pass 400). Each moved file's map entry and "Named next cuts" updated.
- **Spikes:** CO-S1 and CO-S2 run; CO-S3 too when S-KEY1 exists. Verdicts and `rule_sha256` here.
- **Acceptance:** the verdicts recorded; CO-3 and CO-4 rewritten if CO-S2 chose the fallback; CJ-23
  amended if CO-S1 (f) stopped. **Proof rows, mutants, manual checks:** none.
- **Depends on:** CJ0a. **Lane** C. **Questions:** none beyond the samples (S-KEY1).

#### CO0's record (2026-11-01)

**Landed.** Lane C, base `0210dfe7`. The worktree began at `eb350b86` and was fast-forwarded to
the integration head before any edit, because this phase's spec cites CJ2b's CJ-28. CO-1…CO-9, the
CJ-22, CJ-23 and CJ-28 amendments and their index rows were committed alone first (`d7422ca0`),
before the instruments. Then came the instruments `tools/proof/cutout_spike/`: the runner
`cutout_spike.py`, the pure `deciders.py`, the probes `mask_speed.swift` and `mask_track_probe.swift`
with `mask_track_writer.swift`, and its README. Also the proof README's section, the verdicts in
CO-1, CO-3, CO-4 and CO-7, CO-3 and CO-4 rewritten to the mask pack (here and in §11), and this
record. Nothing in `app/`, `core/`, `graphic/`, `mcp-proxy/` or `agent/` changed. The lane filed
no issue; its one draft is filed at integration (**Owed**).

**The host.** macOS 26.5.1 (25F80), Apple M2 Max, on AC power (`pmset` first: "Now drawing from
'AC Power'"). Two other lanes ran throughout. The one-minute load average, read at each row, ran
from 2.8 to 52.0 across CO-S1's rows, and from 5.7 to 56.0 across CO-S2's (70.8 at its start).
CO-S1's rows are medians of three runs; CO-S2's playback rows medians of three interleaved runs,
its build rows medians of ten interleaved.

**Rule hashes (R0).** Each run recomputed CJ-7's hash of its entry, and each matched CJ0a's
record: CO-S1 `035665d178e29749cf6ae5d14e12bb462768b969d84b39bbbd7290f49c9fd05a`, CO-S2
`577a8f392efc3bd086165af2e1f9be01ca480f08cf6c54deca498bad30709eee`. Each `results.json`
(`tools/proof/work/creator_spike/CO-S1/`, `CO-S2/`) stores its value. CO-S3 did not run (S-KEY1).

**Fixtures** (`tools/proof/media/cutout/`, untracked; `cutout_spike/README.md` has how each is
made):
- `push_1080.mov` (H.264) and `push_4k.mov` (HEVC 8-bit): E9's push-in over Photos' FlexAudio cover
  `AAE4E824-DD67-4DB0-933F-AD2D619E4EF6.jpg` (SHA-256 `1f232b43…f0c7bc1b`), padded to 16:9 as E9's
  `person_hero`.
- `screen_4k.mov`: `testsrc2` 3840 × 2160, HEVC.
- `barcode.mov`, `barcode_rev.mov` and `long_60m.mov`: the writer's bar code, 1080p H.264.
- `hlg_vfr.mov`: barcode's first 40 s less frames 119, 270 and 899, HEVC Main 10 HLG. The runner
  read its frame times back as barcode's less those three.

**The verdicts.**

- **CO-S1** (speed only) — `VERDICT standard=person-balanced rate=every realtime_1080=1.81
  realtime_4k=1.62@source,2.10@1920 mask=512x384 first_call_ms=123.8 read_size=owed best=owed
  flicker=owed rotation=owed`. Every request ran fresh, pinned to the Neural Engine
  (`ane(16 cores)`, revision 1 for all three candidates). Median realtime factors:

  | Candidate | Rate | 1080p, source | 4K, source | 4K, long side 1920 | Mask |
  |---|---|---|---|---|---|
  | person `.balanced` | every | 1.81× | 1.62× | 2.10× | 512 × 384 |
  | person `.balanced` | 15 | 4.09× | 3.12× | 4.75× | 512 × 384 |
  | person `.balanced` | 10 | 5.41× | 4.77× | 6.32× | 512 × 384 |
  | person `.accurate` | every | 0.48× | 0.57× | 0.68× | 2016 × 1512 |
  | person `.accurate` | 15 | 1.26× | 1.25× | 1.34× | 2016 × 1512 |
  | person `.accurate` | 10 | 1.20× | 1.94× | 2.06× | 2016 × 1512 |
  | instance, scaled | every | 0.70× | 0.71× | 0.89× | the read size |
  | instance, scaled | 15 | 1.46× | 1.40× | 1.21× | the read size |
  | instance, scaled | 10 | 2.26× | 2.06× | 1.70× | the read size |

  A fresh process's first request took 123.8 ms (`.balanced`), 147.9 ms (`.accurate`) and 415.0 ms
  (the instance mask). `.accurate` at 10 a second below 15 at 1080p, and the instance mask slower
  at 1920 than at the source size on the 4K file, are the shared machine's noise: no rule reads
  them without S-KEY1.
- **CO-S2** — `VERDICT route=mask-pack encoding=none chunk_s=none class=none registration=22/22
  colour_max=0 iou=none edge_mad=none mb_per_min=none playback=100.00 build_ms=+1.7
  fixed_pct=none`. The mask track failed (3) at both encodings, so the pack was measured and kept:

  | Encoding, L | (1) | (2) levels | (3) mean IoU (pooled), edge | (4) MB/min | (5) | (6) ms | fixed |
  |---|---|---|---|---|---|---|---|
  | HEVC, 5 s | 22/22 | 0.062 | 0.9829 (0.9915), 1.14 | 5.86 | 601/601 | +604.1 | 0.92 % |
  | HEVC, 10 s | 22/22 | 0.062 | 0.9829 (0.9915), 1.14 | 5.85 | 601/601 | +170.1 | 0.46 % |
  | HEVC, 30 s | 22/22 | 0.062 | 0.9829 (0.9915), 1.14 | 5.85 | 601/601 | +47.6 | 0.15 % |
  | ProRes Proxy, 5 s | 22/22 | 24.4 | 0.9802 (0.9897), 1.54 | 15.16 | 601/601 | +457.7 | 2.32 % |
  | ProRes Proxy, 10 s | 22/22 | 24.4 | 0.9802 (0.9897), 1.54 | 15.16 | 601/601 | +202.7 | 1.16 % |
  | ProRes Proxy, 30 s | 22/22 | 24.4 | 0.9802 (0.9897), 1.54 | 15.15 | 601/601 | +59.1 | 0.39 % |

  - L would have been 30 s for both encodings, the shortest passing (5) and (6), with one chunk's
    fixed cost 25.3 ms (HEVC) and 64.1 ms (ProRes).
  - (2) is the same with the plain class in SDR and the converting class in SDR and HLG.
  - (3)'s worst frame was 0.565 (HEVC) and 0.682 (ProRes).
  - The pack: (1) 22/22, (2) 0 levels over 120 masks (the stored bytes read back outside any
    composition, so it holds by construction: they never pass AVFoundation), (5) 601 of 601
    frames with its lookup and LZFSE decompression in every request, (6) +1.7 ms (7.05 against
    5.38 ms, reading `long_60m`'s tables, 3,456,020 bytes).
  - Each registration row is eleven cases × every frame and 15 a second, all straddling a chunk
    boundary. At every frame the reverse case read mask index = picture index, as `reversed_time`
    requires.

**What each verdict feeds.**
- CO-S1 → CO-1 and CO1: Standard is person `.balanced` at every frame. Its realtime factor (1.81×)
  is the one CO-S2's fixed-cost percentage used. The read size (e) is owed; the rule's fallback is
  the source size. Best (d) is owed, and with it CO3's Quality control and CO4's Best.
- CO-S2 → CO-3 and CO-4 rewritten to the pack, and CO-7 (no class is chosen for masks: the pack's
  bytes never pass AVFoundation). The CO1, CO2a1 and CO2a2 sections, and the Phases table's CO2a1
  row ("the plan carries mask tracks"), were written for the track: chunk movies in CO-S2's
  encoding, CO-10's encoding and chunk length, and M10's mirrored chunk. Those phases read CO-3 and
  CO-4 as rewritten. With the pack, the plan carries no mask track. The recipe's `cutout` key, CO-8's
  `texture(4)` and CO-6's waits stand.
- The owner's pre-approved fallback (CO0's answer) was not needed: the pack passed.

**Owed.**
- S-KEY1: CO-S1's J, B, flicker and rules (a), (b), (d), (e) and (f), then CO-S3 at CO4's head.
- S-TH1: CO-S1's speed rows.
- S-TH4: CO-S2 (1)'s HLG VFR row on the owner's own file (an `ffmpeg` fixture stood in).
- CO1's head: the CO1, CO2a1 and CO2a2 sections, CO10's "the mask movie" and the Phases table's
  CO2a1 row ("the plan carries mask tracks") still describe the mask track, its chunk movies and
  mirrored chunks; they are rewritten to CO-3 and CO-4's pack before CO1's spec is fixed.
- To file: the pack's storage, 62.32 MB a minute lossless (below), with the candidates delta or
  run-length coding between masks, a lower stored resolution, a lossless video codec in the pack
  and a quantised soft edge, each needing (1), (2) and (3)-like checks and a new size row; filed
  after the integration commit (`ai-drafted`, `low-priority`).

None is a STOP. No manual check.

**A risk the rule does not read.** The pack is lossless. Over CO-S1's 1080p Standard masks (600
masks of 512 × 384, every frame), it took 20,772,076 bytes, 62.32 MB a minute, against the HEVC
track's 5.85. CO-S2's rule judges the pack on (1), (2), (5) and (6) only, so this does not change
the verdict. It is recorded for CO1, whose cache will hold it.

**Instrument rows.**
- `--selftest` 20/20.
- `--build-only` exit 0, both probes through `swift_build.build`.
- `--only s1` and `--only s2` each exit 0, each with `rule_matches: true` and its VERDICT line.
- `spec_index_proof.py` 225/225 and `name_residue.py` exit 0.
- The gate: `make gate` once, after the instruments and the documents, before this line was
  written: "gate: PASS 259s" (names 1 s and test 257 s ran; typecheck, fmt, lint and app were
  skipped, their inputs unchanged). `name_residue.py` was re-run over the record, exit 0.
- The road map names no proof rows, mutants or manual checks for CO0.

**Deviations.**
- The push-ins use the FlexAudio cover first, MUSE only as the fallback (the spec has the
  reverse). A 1080p still of MUSE's back view gave a person `.balanced` mask of at most 45 levels
  with no pixel above 127. The cover gave 246, with 4.25 % above 127. (3) needs a person's edge.
- (3) and (4) read the dump's decoded frame times (`all_pts`). Compressed sample times from
  `push_1080.mov` (with B-frames) had dropped two frames from a chunk in a smoke run, fixed before
  the recorded runs.
- Each timed build runs in its own autorelease pool. Without one, the with-masks times grew over
  the ten runs of a smoke run (154 → 402 ms).
- (6)'s chunk files: chunk 0 written, the rest APFS clones of it. The build opens each file and
  reads its track, and decodes nothing.
- (3)'s IoU is the mean over frames, as CO-S1's J is. The pooled IoU is recorded beside it, and
  both fail.
- ProRes 422 Proxy carries the mask's full-range values in `422YpCbCr8`, a video-range format, as
  the spec set. That is (2)'s 24.4 levels.
- (5)'s canvas is 3840 × 2160 (the spec names none). The pack's VERDICT prints `none` for the
  track's fields. The pack's size row (`pack … size`) has no rule.
- CO-S2 ran twice. Run 1 came before the size row was added and gave the same verdict, with the
  same (1)–(5). Its (6) was +570.5, +140.4 and +46.7 ms (HEVC) and +514.2, +118.4 and +63.7 ms
  (ProRes), and the pack +2.6 ms. The numbers above are run 2's, on the final instrument.

**Review.** One review, verdict pass, four nits, none fixed in the lane; all four resolved at
integration:
- The pack's (2) is the LZFSE round trip of the stored bytes outside any composition, so it
  cannot fail. CO-3, CO-7 and this record now say so beside "0 levels over 120 masks".
- The road map's CO-1 and CO-7 bullets lacked the verdicts §11 carries. CO-1 gains CO-S1's
  Standard, CO-7 CO-S2's "no class is chosen".
- The later sections still describe the mask track: owed to CO1's head (**Owed**).
- `registration_score` took a reversed source's pivot and last end from the frame count, wrong for
  a source with dropped frames (`hlg_vfr`'s 1,197 frames end at 1,200), though no reversed case
  reads one. It now takes the last frame plus one. Re-scoring the lane's four registration files
  (HEVC at 5, 10 and 30 s, and the pack) with it gave 22/22 each, two reversed rows each, all on
  `barcode`; `--selftest` 20/20.

**Integration.** Cherry-picked (`d7422ca0…fe4ea23f`) onto `worktree-creator-jobs` after CU3a1 and
TX1. Conflicts only in the indexes and the decision file, each kept both sides:
`creator-jobs-2.md` held CU3a1's and TX1's blocks and then CO0's, the index's TX-10…TX-14 rows
come before CO-1…CO-9, and its `creator-jobs-2.md` summary kept TX1's clause. That put
`creator-jobs-2.md` at 560 lines, past the series' ~500-line rule (spec §11 `creator-jobs.md`'s
head), so CO0's paragraph and CO-1…CO-9 moved to a new `11-decisions/creator-jobs-3.md` (146
lines): the nine index rows link it, it has its own row, `creator-jobs-2.md` (426) says the series
goes on there, and `creator-jobs.md` (478), this file's head and `cutout_spike/README.md` cite
it. The spec README's `11-decisions/` total is 17837 in 37 files (`spec_index_proof.py`
231/231; `name_residue.py` exit 0). No `CLAUDE.md` edit was owed. `make gate` on the integrated
tree, before this sentence: "gate: PASS 80s" (names 1 s, test 79 s; typecheck, fmt, lint and app
skipped, their inputs unchanged). No Release proof: the road map names none for CO0, and nothing
the app builds from changed.

### TX2b — the tab's bar

- **What a person gets:** the bar pinned above the transcript: Words from (which tracks to read),
  Language, the fill's progress with Stop, the same-speech note, and the clips with no words. Stop
  here withdraws only the tab's want.
- **Decisions:** TX-22's bar half, in TX2a's block.
- **Swift:** new `TranscriptBar.swift` (the Clip tab's `pinnedBlock` shape); `TranscriptPane.swift`
  (the bar and notes); `TranscriptFill.swift` (progress, the tab's want);
  `AgentServer+TranscriptView.swift` (the bar's state; pressing Stop).
- **MCP mirror:** none new; `get_timeline_transcript {tracks, language}` is the agent's Words from
  and Language.
- **Docs:** `transcript.md` (the bar, Stop, the note); spec §4.3e; the screen
  `designs/screens/11c-transcript-tab.md`, light and dark by `screens.py`.
- **Acceptance:** the bar's filters equal the tool's arguments; Stop leaves a tool call's fill
  running.
- **Proof** (`transcript_tab_proof.py` rows, Release): T8 Words from narrows to one track and the
  tokens equal `get_timeline_transcript {tracks}`'s; T9 a second installed language reads a second
  cache file; T10 the bar's Stop during a fill with a tool call waiting: the call still lands its
  words; T11 the screen's capture has no layout problem.
- **Mutants** (2): Words from ignored; the bar's Stop cancelling every want.
- **Manual checks:** none beyond JOB-10. **Depends on:** TX2a. **Lane** A. **Questions:** none.

#### TX2b's record (2026-11-02)

**Landed.** Lane A, on the lane's branch from base `c5934664` (the lane's worktree was made at
`eb350b86`, before TX2a; it was fast-forwarded to the integration head `c5934664` before any
work). No owner question: the road map names none for TX2b, and TX2a's answers of 2026-11-01
stand. Two lane commits: the bar (`c7b3f25a`) and fix pass 1 (`5a44129c`). TX-24…TX-27 were
appended to `11-decisions/creator-jobs-3.md` (243 → 302, 305 after fix pass 1) with four index
rows, and TX-22 and TX-23 got their "Amended 2026-11-02" lines, before the code. No core, FFI,
op or format change, and no product tool. A person gets the bar above the Transcript tab's text:
Words from, Language, the status with Stop or Read, the same-speech notes and at most three
no-words rows; an agent gets nothing new (`get_timeline_transcript {tracks, language}` is
already its Words from and Language), a proof `transcript_view`'s bar arguments.

**What changed.**
- Swift (`wc -l`): `TranscriptBar.swift` new, 290 (the bar; `statusText` moved here from the
  pane); `TranscriptPane.swift` 215 → 172 (gave up its notes stack, `refreshNotes()` and
  `statusText`; builds the one bar in `init` and returns it from `makeHeader()`, the scroll view
  pinned to the pane's top); `TranscriptTabSource.swift` 399 → 514 (Words from, Language, the
  tracks and the installed languages, Stop, Read and `.stopped`; a TX2a file, so the 600 cap,
  and TX2a's anchors `let take = 1` and both `isLiveEditing` blocks byte-identical);
  `AgentServer+TranscriptView.swift` 183 → 309, 314 after fix pass 1 (`words_from`, `language`,
  `stop_after`, `read`, `bar`, `stopped`). Not touched: `TranscriptFill.swift`, `AgentServer+TimelineTranscript.swift`,
  `TimelineTranscript*.swift`, `InspectorViewController.swift`, `transcript_tab_probe.swift`, core.
- Instruments: `transcript_tab_proof.py` (B1–B3 app rows, B4 other row, Z0's nine properties,
  the mutants `words-from-ignored` and `stop-cancels-all`); `screens.py`'s `NOT_SHOWN` gained
  `RCDevCursorLoadHold` (below); the new screen `designs/screens/11c-transcript-tab.md`.
- Documents: spec `04.3e` (the bar, Words from, Language, Stop and Read; 62 → 92), `07.9c`
  (`transcript_view`'s arguments, `bar`, `stopped`; 427 → 441), `07.4` (the row gains
  `TranscriptBar.swift`), the spec index's Lines cells and the §11 total (18,060 in 37 files,
  18,063 after fix pass 1);
  §11 TX-24…TX-27 and their index rows; `docs/guide/transcript.md` (the bar, Stop and Read);
  `docs/developing.md` (`transcript_view`); `tools/proof/README.md`'s TX2b section.

**Commands and results** (three lanes shared the machine).
- `make typecheck`: exit 0 after each Swift change, the four baseline warnings, tsc silent.
- `python3 tools/proof/swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS
  tools/proof/transcript_tab_probe.swift`: exit 0.
- Probe rows `--only T1,T3p,T4p,T5,T7,T8,T9,T10,T13p`: 10/10.
- Debug (`make app-debug`), `--only Z0,M1,T2,T12,B1,B2,B3,B4`: first 7/8. B4 failed twice over:
  `screens.py`'s P2 refused `RCDevCursorLoadHold` (CU3a2's dev launch default, neither pinned nor
  in `NOT_SHOWN`; added to `NOT_SHOWN`), and the window capture in dark held two new layout
  problems, the status label 4 pt wide and Stop at the bar's origin: the 0.25 s poll had shown the
  status row between `snapshot_ui`'s last pass and its layout report. The bar now lays its window
  out when a row comes or goes, and the capture then showed two more faults, fixed: the status
  sentence squeezed to its minimum beside Stop (the row is now `.fill`, the sentence hugging at
  1), and "Automatic (English (United States))" drawn past the popup's chevron at 304 pt (the
  title is now "Automatic (en-US)", TX-25 says so). Then B4 passed: 6 pass of 6, "new problems: 0".
- `python3 tools/proof/spec_index_proof.py`: 234/234.
- `make gate`: "gate: PASS 457s" (names 1 s, typecheck 6 s, fmt and lint skipped, test 243 s,
  app 207 s).
- `RC_PROOF_APP=release env -u RC_ASSEMBLYAI_KEY python3 tools/proof/transcript_tab_proof.py`:
  **22/22**. B1: All tracks 38 tokens, `words_from` the second track 17, equal to
  `get_timeline_transcript {tracks}`'s 17; null equal to the unfiltered call; (b) settled, 21
  tokens, none of ten's, no ten cache file. B2: nine installed languages; A read in en-US, then
  `language: en-AU` kept `2-en-AU.json` beside `2-en-US.json`. B3: (a) the tool call took 6.6 s
  and answered 1,242 words of ten; after it `stop_after` "pressed", status `stopped` ("Stopped. 1
  file not read on this Mac."), `owns_want` false; Read showed 1,242 tokens, idle; (b) 17 answers
  after the press, none wrong, the last "Stopped. 2 files not read on this Mac.", no cache file for
  the 3,625 s WAV. B4 6 pass of 6, no new problem. TX2a's rows unchanged (T6's median 23.9 ms).
- `env -u RC_ASSEMBLYAI_KEY python3 tools/proof/transcript_tab_proof.py --mutant words-from-ignored`
  (a tree copy): **caught**, B1 failed: `words_from` showed all 38 tokens against the tool's 17, and (b)
  read ten (1,242 of 1,263 tokens, `3-en-US.json` kept). `--mutant stop-cancels-all` (a tree copy):
  **caught**, B3 failed: the tool call answered "The transcription was cancelled." after 3.1 s. TX2a's
  seven mutants were not re-run: no anchor line they edit changed.
- `python3 tools/proof/proof_app.py launch --app release`: `grep "Frame Job: "` on its log printed
  nothing; the instance was stopped by its pid.

**Deviations.**
- **The base.** The worktree was made at `eb350b86`; it was fast-forwarded to the integration
  head `c5934664` (TX2a's) before any work.
- **The rows are B1–B4**, not the road map's T8–T11, which are TX2a's probe rows.
- **"Automatic (<identifier>)"**, not the default's name: the name runs past the popup's chevron
  at the inspector's width (`OptionPopupControl` is not forked and draws without truncation).
- **`screens.py`'s `NOT_SHOWN` gained `RCDevCursorLoadHold`**, a file outside the spec's list:
  P2 failed on it for every `screens.py` run since CU3a2, so B4 could not pass without it.
- **The bar lays its window out when a row comes or goes** (`layoutSubtreeIfNeeded` on the
  window's content view), so a layout read between passes never sees a re-attached view at a zero
  frame.
- **"N files" is pluralised** ("1 file", "2 files") where TX-26 writes "N file(s)".

**Fix pass 1 (`5a44129c`, review 1's should-fix).** `checkBar` checked `read` against
`readShown` before `words_from` or `language` were applied, and a new track or language empties
the misses, so `{language: X, read: true}` on a stopped tab answered ok without pressing Read. The
server thread now refuses `read` together with `words_from` or `language` (an explicit null
included) before any `onMain` hop: "read presses the bar as it is; set words_from or language in a
call of their own."; TX-27, §7.9c and the tool's description name it. Run: `make typecheck` the
four baseline warnings; `spec_index_proof.py` 234/234 (233/234 first, the §11 total 18,060 against
`wc -l` 18,063, fixed); `make gate` "gate: PASS 424s"; Release `--only Z0,B2,B3` 3/3 (B3's call
6.3 s); on the fixer's Release instance `{read: true, language: null}` and `{read: true,
words_from: 1}` answered the refusal, `{read: true}` alone passed it, and `grep -c "Frame Job: "`
printed 0. The rest of the proof and both mutants were not re-run: no row passes `read` with
`words_from` or `language`, and the mutants' anchors are untouched.

**Reviews.** Review 1 (`c5934664..c7b3f25a`): one should-fix (fix pass 1) and two nits, left as
they stand: `stop_after` is scheduled in the final hop, after `wait`, where TX-27 and the
description put it before; `stopAfters` is never cleared, so `bar.stop_after` reads the last
press's outcome. Review 2 (`c5934664..5a44129c`): pass, with two nits: this record's figures and
its missing review paragraph (done at integration), and no proof row exercising a TX-27 refusal
(only the fixer's hand check covers the `read` one), left as it stands.

**Integration (2026-11-02).** Cherry-picked onto the integration branch at `c5934664` with no
conflict and no format change. The `CLAUDE.md` edit owed went in: `app/CLAUDE.md`'s
Transcript-tab entry gained `TranscriptBar.swift` and the sentence on the bar (the pane's one
`makeHeader()` instance; Words from and Language on the source; Stop the tab's want only, or Read;
the notes and at most three no-words rows). `make gate` on the merged tree: names, typecheck, test and app `pass` (fmt and lint skipped, no
Rust changed), "gate: PASS 302s".

**Owed.** JOB-10 (a person) covers the tab; nothing new for a person. Nothing filed.

### CU1b — the recorder saves the cursor

- **What a person gets:** every display, window or picked recording writes `<stem>.fjcursor` beside
  each segment movie: the cursor's path and images, every click and scroll, and the frames'
  geometry. The pointer is still burned in (CU3c flips it). `record_screen`'s answer names each
  segment's cursor file.
- **Swift:** `CursorCapture.swift` (CU-S1's position source — a 120 Hz poll on its own queue,
  changes only — its click and scroll source, and the image sampler at most 10 Hz plus each
  mouse-down on the thread CU-S1 found safe, deduplicated by bytes, a nil sample recording no
  change); `ScreenFrameWatch.swift` gains geometry changes from `SCStreamFrameInfo` and the dirty
  box when CU-S3 passed, inside the file (its state is `private`; about 240 lines after); the pure
  `ScreenFrameWatchRule` there (`attaches(camera:cursor:)`, `resumeSteps(attached:)`);
  `ScreenRecorder+Cursor.swift` (capture starts with the stream; one buffer per segment, closed at a
  pause and opened at a resume; at a segment's close the movie's track size goes to
  `closeSegment(movieSize:)`, then `CursorFileWriter`); the watch goes on with cursor capture
  (CU-13); `RecordingResult` segments gain `cursorURL` and `cursorProblem`; the landing note names a
  cursor problem and a segment written with `cursor_image: none`.
- **MCP:** `record_screen`'s answer gains `cursor_path` per segment, `cursor_problem` when set, and
  `cursor_image: "none"` when no image was recorded.
- **Docs:** `docs/guide/screen-recording.md` ("Files and formats"); spec §7.9d; `app/CLAUDE.md`;
  `docs/manual-checks.md` (JOB-20).
- **Decisions (draft):** **CU-11** the capture sources and rates from CU-S1 (positions polled at 120
  Hz or from events; images at most 10 Hz plus each mouse-down; a nil checked per sample). **CU-12**
  the anchor from CU-S2; a segment with no E2 uses E1 and its file says so. **CU-13** the watch on
  every screen recording (amending CAM-9 (3), recorded at CU0a).
- **Acceptance:** the ungranted probes pass; a granted Release recording at Nominal and Best,
  display and window, with a pause and resume, lands every segment, each file passing the core's
  check.
- **Proof rows:** *ungranted* (`cursor_capture_probe.py`): K0 `ScreenFrameWatchRule` attaches with
  cursor capture and no camera, and is removed and re-added around a resume whenever attached; K10
  the image sampler asks at most 13 times over 1 s of synthetic moves and 3 clicks. *Granted*
  (`cursor_proof.py`, Release; skipped by name without Screen Recording; extra coverage, never a
  mutant's only killer): K1 samples mapped by CU-S2's mapping against the burned tip ≤ 1.5 px p95;
  K2 time error ≤ one frame over moving frames; K3 a window moved and resized mid-recording within
  K1's bound; K4 pause and resume land two segments, each with its own anchored file; K5 posted
  clicks appear at their positions (skipped without Accessibility for the poster); K6 CPU added by
  the watch and samplers ≤ 3 % of one core; K7 an unwritable folder lands the movie with
  `cursor_problem`; K8 an odd-size window's `movie_size` equals the movie's, K1's bound held; K9 a
  still-start segment names E1 within CU-S2's bound.
- **Mutants** (3): the watch off without a camera (K0); the watch not removed for a resume (K0); the
  sampler unthrottled (K10).
- **Manual check:** **JOB-20** — a real recording with real clicks: the file's click count equals
  the clicks made.
- **Depends on:** CU1a, CU-S1, CU-S2. **Lane** B.
- **Question for the owner:** the cursor file beside the movie or in a per-recording folder?
  *Recommended: beside, `<stem>.fjcursor`*, the microphone and camera files' convention.

### CO1 — person masks on the Mac

- **What a person gets:** nothing visible. An agent gets `get_media_analysis {kind: "masks"}`: the
  runs of a media's person masks for a window, made on the Mac and kept in the package as one
  lossless pack per media (CO-3, CO-4 as CO0 rewrote them: no mask track, no chunk movie, no
  mirrored file).
- **Head:** CJ-S2's rule 1 re-run for the mask request (the device; a pick other than the Neural
  Engine re-measures Standard on it and takes CO-S1's speed-only rate), and CJ-S3 (b) re-run with a
  masks job (the playback pause); verdicts recorded, CJ-21 amended if (b) fails, the pause then for
  the `masks` kind only.
- **Toll first:** `AgentServer+Analysis.swift`'s `AnalysisClipTimes` → `AnalysisClipTimes.swift`,
  a pure move.
- **Core:** none (CJ-20).
- **Swift:** `AnalysisMasks.swift` (the `masks` kind: a fresh person `.balanced` request per frame,
  revision 1, on the pinned device, at CO-11's rate and the source size, the found flag, the runs,
  the job's publishes every 30 s and at each range's end); `MaskPack.swift` (the pack's bytes: the
  LZFSE masks in append order, a frame table sorted by time, a mask table, a 40-byte footer; its
  append-merge writer and its mapped reader); `AnalysisFrames+InputPass.swift` (CO-7's third arm:
  `AVAssetReaderTrackOutput` and step 0's `InputPass`, every frame's own time kept);
  `AnalysisFrames.swift` (`Source.arm`, wiring only); `AnalysisStamp.swift` (`masks`,
  `AnalysisVisionStamp`); `AnalysisStore.swift` (`publishFile`, a hit needing its payload file);
  `AgentServer+AnalysisMasks.swift` (the answer's runs); `AnalysisLane.swift` (the `.masks` arm,
  and the pause if CJ-S3 (b) chose it).
- **MCP mirror:** `get_media_analysis` gains `masks`; its prose names the answer (`mask_size`,
  `frames`, `subject_found`, runs with `subject_found` and frame count, the stamp, no pixels) and
  that a person's path is Remove Background (CO3).
- **Docs:** `app/CLAUDE.md`; spec §5.6 (`cache/analysis/masks/`), §7.4, §7.9e; `docs/guide/mcp.md`,
  `projects-and-media.md`.
- **Decisions:** **CO-10** the pack (its bytes, the append-merge publish, the size Vision answers,
  the found flag, revision 1, the source read size); **CO-11** the device and rate; **CO-12** CJ-S3
  (b) with masks; **CO-13** the third arm; **CO-14** the answer; **CO-15** the owner's answer, and
  M10 and the centroid moved on.
- **Acceptance:** the head's verdicts recorded; proof rows against Release; `make gate`.
- **Proof** (`co1_proof.py`: probe rows through `co1_probe.swift`, app rows through
  `get_media_analysis`): P1 a pack's fresh write reads back byte-exact; P2 two publishes of
  disjoint ranges in either order give the union, earlier blobs in place; P3 `shown(at:)`; P4 the
  found flag at 0.5 %; P5 the stamp's `vision` field; P6 a throwing write leaves the store as it
  was; P7 a publish waits for a save; P8 `runs` and the capped rate's `covered`; P9 a marker whose
  pack is gone, garbage or another size misses and is rebuilt with the job's coverage alone. M1 a
  60 s 1080p30 person fixture asked for 12–37 s writes a pack whose frame table is exactly that
  window's frames at their presentation times, once each; M2 the folder removed and asked again:
  masks within 1/255; M3 the stamp names kind version, request, quality, revision, rate, read size,
  OS build and device, and no path; M4 an Apple Log and an HLG twin through the third arm give mean
  IoU ≥ 0.98 against the SDR push-in's masks, their frame tables the files' own times; M5 a
  rotation-tagged twin, and a portrait pair, give masks within 1/255; M6 a relink: a miss, the
  stamp's source changed, the pack holding only the new run's frames; M7 saves during a job never
  find a half pack and are never refused; M8 closing the document cancels the job and nothing is
  written after; M9 (Release) realtime at least 0.8 × CO-11's Standard factor; M11 (only with the
  pause) a masks job waits out `play_preview`, and a `shots` job does not.
- **Mutants** (8, +1 with the pause): the device unpinned (M3); `.fast` substituted (M2); times one
  frame off (M1); the third arm through a composition (M4); the marker before the pack (P6); a
  range's end dropped (M1); the found threshold moved (P4); the hit without its pack (P9); no pause
  (M11).
- **Manual checks:** none. **Depends on:** CO0, CJ2a. **Lane** C.
- **Question for the owner:** a cut-out clip's analysis starts as soon as it is asked for, or after
  the Background render delay (G-38)? *Recommended: at once* — it is the result the person is
  waiting to see — with CJ-S3 (b)'s pause while playing if it chose one. **Answered 2026-11-01: at
  once** (CO-15, for CO2b's CO-22).

#### CO1's record (2026-11-02)

**Landed.** Lane C, base `5dbcd8fc`. The worktree began at `eb350b86` and was fast-forwarded to
the integration head before any edit. The commits, in order:
- `f8a0e675`: toll T-CO1, `AnalysisClipTimes` out of `AgentServer+Analysis.swift` (373 → 336)
  into `AnalysisClipTimes.swift` (38), a pure move, `make typecheck` alone.
- `eb29dd45`: the head. CJ-S2's rule 1 and CO-S1 re-run, CO-10…CO-15 recorded, and this road
  map's CO1, CO-21, CO2a1, CO2a2, CO2b and Phases rows rewritten to the pack. That commit came
  before the app code.
- `4b3d7698`: the app code, its documents and the instruments.
- `3c8e9883`: this record; then review fix passes `f4e8822f` and `02f296cb`.

No core, FFI or format change (CJ-20). The product tool count stays 107. An agent gets
`get_media_analysis {kind: "masks"}`; a person sees nothing.

- **New files** (`wc -l`): `AnalysisMasks.swift` 313, `MaskPack.swift` 260,
  `AnalysisFrames+InputPass.swift` 180, `AgentServer+AnalysisMasks.swift` 61,
  `AnalysisClipTimes.swift` 38.
- **Changed:** `AnalysisStamp.swift` 183 → 206, `AnalysisStore.swift` 221 → 258,
  `AnalysisFrames.swift` 385 → 394 (`Source.arm`; `pump`, `preferredTransform`, `halfToBGRA`,
  `Upright` internal), `AnalysisLane.swift` 320 → 324 (the `.masks` arm),
  `AgentServer+Analysis.swift` 336 → 348 (`AnalysisCall` internal; the answer split into common
  fields, `shotsFields` and `masksFields`), `AgentCatalog+Analysis.swift` 103 → 111.
- **Not touched:** `BackgroundRender.swift` (CJ-S3 (b) did not fire), and the generic callers of a
  kind (`AgentServer+AnalysisJob.swift`, `ShotSplit.swift`, `AnalyzingSheetController.swift`).
- **Instruments:**
  - `cutout_spike/`: `--only device`, `--device`, `deciders.device_rule` with five selftest rows
    (25/25), and M5's rotation fixtures.
  - `creator_spike/rule.py`: `write_results(…, folder=)`.
  - `creator_spike/lane_spike.py`: `--playback --kind masks`.
  - `co1_probe.swift` (P1–P10, and the `compare` mode the app rows read masks through) and
    `co1_proof.py` (P1–P10, M1–M9, Z1, eight mutants; P10 from review fix pass 1).
- **Documents:** spec §5.6 (286 → 301), §7.4 (row 48), §7.9e (503 → 513) and their index
  cells, `creator-jobs-3.md` (146 → 281) with six index rows, `docs/guide/mcp.md`,
  `projects-and-media.md`, and both proof READMEs.

**The head.** The host was macOS 26.5.1 (25F80), Apple M2 Max, on AC power (`pmset`: "Now drawing
from 'AC Power'"), with three lanes on the machine.

- **CJ-S2 rule 1 for the mask request** (`rule_sha256` `c41417fb…95bb2b11`, matching):
  `VERDICT device=gpu branch=1 identical=cpu:yes,gpu:yes,neural_engine:yes
  realtime=cpu:0.34,gpu:1.89,neural_engine:1.60 compare=cross_run`.
  - Runs, every frame of `push_1080.mov` (600 masks of 512 × 384, revision 1): CPU 0.476, 0.338
    and 0.319×; GPU 0.981, 1.928 and 1.892×; Neural Engine 1.945, 1.603 and 0.916×.
  - One-minute loads were 12.5…23.3.
  - Each device's three digests were equal to one another, and the three devices' digests
    differed from each other.
- **Standard re-measured on the GPU** (CO-S1's `rule_sha256` `035665d1…9fd05a`, matching):
  `VERDICT standard=person-balanced rate=every device=gpu realtime_1080=1.23
  realtime_4k=1.59@source,1.98@1920 mask=512x384`.
  - At 1080p30: every frame 0.917, 1.228 and 1.971×; 15 a second 3.93×; 10 a second 5.44×.
  - Loads were 9.6…44.
  - The rate stays every frame, and 1.228× is M9's Standard factor.
- **CJ-S3 (b) with masks** (`rule_sha256` `209c6f01…f0309ce830`, matching; Release, PID 45721,
  stopped after): `play_preview` composed 599, 600 and 600 frames idle, and 600, 600 and 600 with
  a masks job wanted on another document over the still's first 120 s. That is a 0.0 % drop, so
  **no pause** (CO-12): CJ-21 is unamended and there is no M11 or `no-pause` mutant. Each busy
  run's job had started and not ended when its play returned; closing its document cancelled it.
- The results files are `tools/proof/work/creator_spike/CJ-S2-masks/`, `CO-S1-gpu/` and
  `CJ-S3-masks/results.json`, each storing its `rule_sha256` with `rule_matches: true`.

**Commands and results.**
- `make typecheck` after the toll and after the app code: exit 0, the four baseline warnings.
- `swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS tools/proof/co1_probe.swift`: exit 0.
- `co1_proof.py --only P1,…,P9`: 7/9 at first. P5 and P8 failed because the PNG fixture did not
  probe (below). After the fix, 9/9.
- `analysis_proof.py --only P1,…,P9`: 9/9.
- Debug (`make app-debug`), the whole proof: 16/18.
  - M7 and M8 failed on the instrument. M7 asked `analysis_job` to wait 120 s (its bound is 60),
    so its job was left running, and M8's job then queued behind it at width 1. Fixed: M7 closes
    its document, and M8 fails by name if its job never starts. `--only M7,M8` was then 3/3.
  - M9 was skipped by name (Release only).
  - The third arm reads about half a frame a second on Debug, so M4 took about 20 minutes there.
- `make gate`: the first run failed test on two Lines cells, `creator-jobs-3.md` and the
  `11-decisions/` total. Fixed, then "gate: PASS 92s" (names, test and app ran; typecheck, fmt and
  lint were skipped). Over this record, before this sentence: "gate: PASS 1s" (names alone ran).
- **Release** (`RC_PROOF_APP=release`, after the gate's `make app`), on the final instrument:
  - `co1_proof.py`: **19/19**. M9's realtime was 1.792, 1.784 and 1.782×, median 1.784× against
    0.982 (0.8 × 1.228).
  - `analysis_proof.py`: **22/22**.
- Z1 printed nothing on every launch.
- `spec_index_proof.py` 231/231; `name_residue.py` exit 0.
- **Mutants** (eight; the app's five built in tree copies as Release):
  - `marker-before-pack` (P6), `found-threshold` (P4) and `missing-pack-hit` (P9): CAUGHT.
  - `device-unpinned`: CAUGHT on M3 (the stamp's device `auto`).
  - `fast-quality`: CAUGHT on M2 (masks 256 × 192, not 512 × 384; its two runs were
    byte-identical, so the size is what catches it).
  - `times-off-by-one`: CAUGHT on M1 (every pts one frame late).
  - `converted-via-composition`: CAUGHT on M4. The HLG twin's table held the composition's
    20067, 40134 … in place of the file's 20000, 40000 …; the Apple Log twin, at an even 30 fps,
    passed.
  - `range-end-dropped`: CAUGHT on M1 (749 frames, coverage [[360, 1108]]).
  - Each was built in about 150–200 s and the copy removed after.

**What the rows found.**
- The pack's mask is 512 × 384 for every landscape media read and 384 × 512 for the portrait pair,
  whether coded 360 × 640 or rotated by its track's transform (CO-10).
- M2's second run was byte-identical to the first (max difference 0 over 750 masks), as were M5's
  rotated twins (90 masks each).
- The push-in's person is weak. M1's 25 s window answered 57 runs, its `found` flag flickering.
- A scratch probe read frame 60 of each M4 twin through the third arm and through the one-clip
  composition's reader. The two pictures were byte-identical for both twins: the third arm is
  step 0's picture.

**Deviations.**
- **M5's fixtures are uncompressed BGRA in MOV (`rawvideo` bgra), not PNG.** AVFoundation on macOS
  26.5.1 refuses PNG in MOV ("Cannot Decode", -11833). An `rgb24` twin decoded 0.65 levels apart
  from its original (mean); BGRA twins decode identically.
- **M4's person is the owner's talking head** (`owner-sync/IMG_0018.MOV`, gitignored and never
  committed; without it M4 is skipped by name and owed), not the push-in. A plain HEVC re-encode
  of `push_1080.mov`'s first 150 frames kept a mean IoU of only 0.73 of its masks
  (`mask_speed dump`, scored on every other pixel). The same re-encode of the talking head's first
  150 frames kept 0.985. M4 prints the talking head's floor beside its rows (HEVC 10-bit at
  40 Mb/s: mean 0.9895).
- **M4's HLG twin inverts GR-15's HLG arm into SDR** (`hdr_proof.convert`, in closed form), not
  `InputConversions.liftSDR`. The lift is HD-3's mapping into an HLG project. A lifted twin read
  back 34 levels darker (frame 60's mean 127 against 93) and kept a mean IoU of 0.9707, below the
  bar.
- **M4 reads 0–10 s** (both of the HLG twin's dropped frames) to bound the Debug run.
- **M4 scores its frame table on the media's own grid.** The HLG twin probes at 29.9 fps (598
  frames in 20 s), and CJ-23's first-frame-wins grid drops one of the two frames that round to an
  index. Its table held 297 of the file's 298 frames in the window, each at the file's own pts.
- **M2 also requires CO-10's 512 × 384**, so `fast-quality` is caught on the size if not the bytes.
- **The app mutants were built as Release** in their tree copies, for M4's speed. The spec names no
  configuration.
- The spec's M10 moved to CO2a2's D16 and the centroid to CO3, as CO-15 records.
- M4 results on Release: Apple Log mean IoU 0.9801 (median 0.9977, 5 frames under 0.9); HLG
  0.9865 (median 0.9981, 5 under 0.9). Both pass 0.98, the Apple Log twin by 0.0001.

**Owed.**
- S-TH4: CJ-S3 (b)'s and CJ-S2's rows on the owner's own HLG VFR file (the synthetic 1080p file and
  the push-in stood in).
- S-KEY1's CO-S1 rows (Best, the read size, flicker, rotation), as CO0 owed them.
- To file: a timed-out call loses up to one publish interval of a job's work. A tool call that
  passes its 60 s bound releases its owner, which cancels the job, and a masks job publishes only
  every 30 s and at a range's end. So each further call keeps only what was published. It matters
  for slow kinds; `shots` is fast. Filed after integration (`ai-drafted`, `low-priority`).

None is a STOP. No manual check.

**Review.** Review 1 found two should-fix items and three nits; fix pass 1 fixed the two:
- A job whose range decoded no frame (every index a dropped VFR frame) has no mask size, and its
  publish wrote a fresh 0 × 0 pack over the populated one, shrinking the coverage to the empty
  range. `MaskPack.write` now merges a write with no masks onto the on-disk pack at the pack's own
  size. New probe row P10 publishes 0 × 0 with no frames onto a 600-frame pack: against the
  unfixed writer it failed ("merged false … size 0×0 … coverage [[600, 600]]"); fixed, it passed.
- `get_media_analysis`'s description sent a person to Remove Background, which is CO3 and not
  built. It now says no menu or pane reaches masks yet.
- Verified: `co1_proof.py --only P1,…,P10` 10/10 (Debug probe); `make gate` "gate: PASS 398s"
  (names, typecheck, test and app ran; fmt and lint skipped); Release
  `co1_proof.py --only P10,M1,M2,M6,Z1` 5/5. No mutant anchor was touched.
- Review 2 (`5dbcd8fc..f4e8822f`, fix-required): one should-fix. CO-10 and §5.6 still said a pack
  of another size is written fresh, against the fixed writer. Fix pass 2 (documents only) added
  the exception to both ("a publish that made no mask (a range of only dropped frames) merges onto
  the pack at the pack's own size"), `05.6` 301 → 303, `creator-jobs-3.md` 281 → 284;
  `spec_index_proof.py` 231/231 (230/231 first, the §11 total), `make gate` "gate: PASS 252s". No
  code or instrument changed, so the Release proof and the mutants were not re-run.
- Review 3 (`5dbcd8fc..02f296cb`): pass, four nits. Two done at integration: CO-12's "*Pending its
  run.*" label dropped, and the CO0 tolls line now says `plan_segment.rs` lapsed for CO (no
  `mask_of`). Two left as they stand: a media's first job that makes no mask writes a fresh 0 × 0
  pack, so `mask_size` answers `[0, 0]` until a job makes masks; and `offset + length` in
  `MaskPack`'s table check traps on overflow in a hand-damaged pack instead of a named
  `MaskPackError`.

**Integration (2026-11-02).** Cherry-picked (`f8a0e675…02f296cb`) onto the integration branch
after TX2a and TX2b, with no format change. Conflicts only in the indexes and the decision file,
each kept both: `creator-jobs-3.md` holds TX2a's and TX2b's blocks and then CO1's (443 lines),
CO-10…CO-15's index rows follow TX-20…TX-27, the file's Holds cell gained CO1's clause after
TX2b's, and the spec README's `11-decisions/` total is 18207 in 37 files
(`spec_index_proof.py` 234/234). The `CLAUDE.md` edit owed went in: `app/CLAUDE.md`'s analysis
entry names the five new files, says a job writes through `publish` or `publishFile`, and gains
the paragraph on the `masks` kind, `MaskPack`, `publishFile`'s rules, the third arm,
`AnalysisClipTimes` and the answer. `make gate` on the merged tree: names, typecheck (the four
baseline warnings), test and app `pass` (fmt and lint skipped, no Rust changed), "gate: PASS
322s". No Release proof re-run: every file CO1 changed in `app/Sources` and its instruments is the
lane's byte for byte (TX2a and TX2b touched none of them), and the lane's Release run, 19/19 and
22/22, stands.

### TX3 — delete words

**Split by size (2026-11-02):** TX3a builds everything below but the pause token (TX-30…TX-33, its
record below); TX3b builds the pause token — a selectable token for a voice-cache pause over 1 s,
cutting `[end of the speech before + 0.2 s, next onset − 0.2 s)`, and `pauses[]` with their
ranges in `get_timeline_transcript` — as TX-34, in its own pipeline after TX3a lands and before
CP1. The decisions below are the drafts; spec §11 holds TX-30…TX-33 as recorded.

- **What a person gets:** select words by drag, ⇧-click or ⇧-arrows; the timeline shades the cut as
  the in/out range. ⌫, Edit ▸ Delete or Edit ▸ Ripple Delete takes them out on every unlocked track
  as one step "Delete Words", from the first word's onset to the next kept word's onset, so the
  pause before the cut stays and the one after it goes (up to 1 s). Words of other clips the cut
  would take are added to the selection first. A selection with a word that cannot be cut, one that
  would leave a locked track's words behind, or one that would pass the clip ceiling is refused in
  its own sentence. A pause token can be selected and deleted (it shortens to 0.2 s each end).
- **Head:** TX-S3 runs; TX-30 records its verdict; then TX-31…TX-33.
- **Decisions (draft):**
  - **TX-30 — A word's cut runs from its onset to the next kept word's onset.** A word's onset is
    the end of the latest voice-cache non-speech run (probability under 0.5, at least two 32 ms
    cells) lying between the previous word's midpoint and this word's midpoint, less a guard G (64
    ms until TX-S3). Midpoints are lead-corrected (`CaptionPages.lead(for:)`: +270 ms on this Mac,
    −60 ms for AssemblyAI); the previous word is the previous word of the same instance (same nest
    path and clip) and media; a clip's first word's window opens at the clip's start; the onset is
    never before the previous word's lead-corrected end; with no such run (continuous speech) or no
    voice cache, the onset is the corrected transcript start. A run w_i…w_j cuts `[onset(w_i),
    min(onset(w_next), end(w_j) + 1 s))`, w_next the next shown word in timeline order (none:
    `end(w_j) + G`). A word's own `cut_start`/`cut_end` are its run of one, so cutting words one at
    a time and together make the same timeline (except across a pause over 1 s, the pause pass's).
    Snapping is `ripple_delete_ranges`' own. A pause token cuts `[end of the speech before + 0.2 s,
    next onset − 0.2 s)`. TX-S3 may replace E2 by E1 or E0. Risk accepted: in continuous speech a
    fragment of a deleted word can remain.
  - **TX-31 — A word selection is the in/out range, and ⌫ in the transcript ripples.** Selecting
    words sets the document's range to the selection's cut range (`set_range`'s door), so the
    timeline shades what will go and Loop plays it. ⌫, ⌦, Edit ▸ Delete and Edit ▸ Ripple Delete,
    with the view first responder and words selected, send one `ripple_delete_ranges`, step name
    "Delete Words"; the range then clears and the playhead lands at the cut. (⌫ lifts on the
    timeline; deleting text closes the gap.)
  - **TX-32 — The tab refuses a cut before sending it**, in this order: a word that is not editable
    (TX-11's reason); locked words left behind ("Track <name> is locked and has words in this cut:
    unlock it to cut here."); the clip ceiling — the tab counts the clips the cut would leave as
    `check_caps` counts them (the current count, plus one per unlocked-track clip running from
    before a merged range's start to after its end, less one per unlocked-track clip wholly inside
    one), and past `RC_MAX_CLIPS` says "This cut would make <N> clips; a project holds at most
    <RC_MAX_CLIPS>. Lock a track that needs no cut, such as a music bed, or cut less." and sends
    nothing (the core's check stays the backstop; `CaptionLayout.swift:288` is the precedent). Any
    shown word the range partly covers is added to the selection first, until nothing is added. This
    bet never raises `MAX_CLIPS` (CJ-9).
  - **TX-33 — An agent cuts words with `ripple_delete_ranges`**, one range from the first word's
    `cut_start` to the last's `cut_end`; no new edit tool; the step is "Ripple Delete" (TR-12).
    Amends TR-11's prompt bullet: "Cutting words: `get_timeline_transcript` answers the timeline's
    words in order, each with the `cut_start` and `cut_end` the Transcript tab cuts it by; cut a run
    of words with one `ripple_delete_ranges` range from its first word's `cut_start` to its last
    word's `cut_end`. `detect_fillers` answers the filler words as ranges. A false start that
    repeats no words is a judgement of meaning, so cut one only when the person asks: say which
    words you will cut, then cut them in one `ripple_delete_ranges` call." TX5, TX6 and TX7 extend
    it, each with its own Amended line.
- **Core, FFI:** none.
- **Swift:** new `TranscriptCut.swift` (pure: onset, `cut_start`/`cut_end`, a run's range, a pause's
  range), `TranscriptCut+Plan.swift` (selection to ranges, the widening, TX-32's refusals, the clip
  count), `TranscriptView+Delete.swift`. Changed: `EditorViewController+Timeline.swift` (489; the
  delete family forwards to the view when it is first responder with words selected);
  `AgentServer+TimelineTranscript.swift` (`cut_start`, `cut_end`, and `pauses[]` with their ranges);
  `AssistantPrompt.swift` (TX-33's paragraph; `assistant_prompt_proof.py`'s digest re-pinned (`make
  test` checks it)).
- **MCP mirror:** the words' `cut_start`/`cut_end` and one `ripple_delete_ranges` (TX-33).
- **Docs:** `transcript.md` (selecting, deleting, where a cut falls); `editing.md` (⌫ in the
  transcript ripples); `menus-and-shortcuts.md` (the tab's keys); spec §4.3e; §11 TX-30…TX-33 and
  TR-11's line; `app/CLAUDE.md`; `docs/manual-checks.md` (JOB-11).
- **Acceptance:** TX-S3's verdict holds on the proof's fixture; one at a time and together give the
  same project.
- **Proof** (`transcript_cut_probe.swift`, `transcript_cut_proof.py`, Release): C1 on the `say`
  fixture every edge in the silence before a kept word, no clipped onset; C2 one at a time and as
  one selection give byte-identical placements; C3 the 1 s cap (a cut before 20 s of B-roll takes 1
  s of it); C4 crosstalk: the other track's overlapping word is selected and cut; C5 a locked
  track's words give TX-32's sentence and no step; C6 a cut past `RC_MAX_CLIPS` gives the cap
  sentence with the predicted count and no step, and one clip under applies with the count equal to
  the prediction; C7 the tab's Delete (`transcript_view` selects, `perform_menu_item` Edit ▸ Delete)
  is one step "Undo Delete Words" whose placements equal `ripple_delete_ranges` of the read's
  ranges; C8 two WAV exports decoded to PCM are equal sample for sample — after the tab's Delete
  Words, and after `ripple_delete_ranges` of the read's ranges on the original — both through the
  always-on master limiter.
- **Mutants** (8): guard 0; the 1 s cap removed; start and end snapped in different directions; the
  widening off; the locked refusal off; the fallback without the lead correction; the cap check
  skipped; the count missing the clips spanning a whole range (C6).
- **Manual check:** **JOB-11** — word cuts on S-TH1: no word's start clipped, no fragment of a
  deleted word left, and the pause after a cut sounds natural.
- **Depends on:** TX2a; TX-S3 at its head. **Lane** A.
- **Questions for the owner:** (1) ⌫ ripples in the transcript and lifts on the timeline: right?
  *Recommended: yes* (lifting words would leave black holes). (2) A word selection sets the
  timeline's in/out range? *Recommended: yes.*

#### TX3a's record (2026-11-02)

**Landed.** Lane A, base `ef2ccde5` (I's HEAD with TX2b; the lane worktree was made at `eb350b86`
and fast-forwarded to it before any edit). One commit with the code, the spike, the probe, the
proof, the decisions and the documents, landed on `worktree-creator-jobs` as one commit. The
pause token is TX3b's (TX-34), split off by size. No core, FFI, op, format, product tool or key
change: the parity check is untouched; `get_timeline_transcript` gains two keys per word and the
dev tool `transcript_view` its tokens' keys and `cut`. Nothing here sends anything (CJ-3).

| File | Lines | What |
|---|---|---|
| `app/Sources/TranscriptCut.swift` | 279 | pure: E0/E1/E2, `sourceOnsets`, `latestRunEnd`, `edges`, the shown-word `Table` and a run's `cut` (TX-30) |
| `app/Sources/TranscriptCut+Plan.swift` | 186 | pure: widening, the refusals and their sentences, the counts after and at the peak, the snapping, `plan`, `wordCut` (TX-30, TX-32) |
| `app/Sources/TranscriptView+Delete.swift` | 39 | the drag selection, `deleteKey()`, `adopt` |
| `app/Sources/TranscriptView.swift` · `+Highlight` · `+Keys` | 361 · 83 · 110 | `onSelect`, `onDelete`; `select` tells `onSelect`; ⌫ (U+007F) and ⌦ → `deleteKey()`; the ⇧ branch tells `onSelect` |
| `app/Sources/TranscriptPane.swift` | 237 | `TranscriptHost`'s four new members; `selectionChanged`, `deleteWords`, `rangeSet`, the re-plan after a rebuild |
| `app/Sources/TranscriptTabSource.swift` | 556 | each media's voice cache beside its pause set, `allWords`, `cutTable()` once per rebuild (every TX2a/TX2b mutant anchor byte-identical) |
| `app/Sources/EditorViewController+Transcript.swift` · `+Timeline.swift` | 78 · 494 | the host's members, `transcriptHoldsWords`, the delete family's forward and its two validator arms |
| `app/Sources/AgentServer+TimelineTranscript.swift` · `+TranscriptView.swift` · `AgentCatalog+Transcript.swift` | 265 · 336 · 79 | `cut_start`/`cut_end` (`wordCut`), the voice caches read on the server thread, `wordRow(_:cut:)`, `transcript_view`'s `cut`, the descriptions |
| `app/Sources/AssistantPrompt.swift` | — | TX-33's paragraph in place of TR-11's |
| `tools/proof/transcript_spike/cut_spike.py` · `.swift` | 264 · 82 | TX-S3 |
| `tools/proof/transcript_cut_probe.swift` · `transcript_cut_proof.py` | 356 · 748 | U0–U6, Z0, C1–C9, C4b, ten mutants |
| `tools/proof/transcript_tab_proof.py` · `transcript_proof.py` · `assistant_prompt_probe.swift` | — | T4 wants TX-31's planned click; `FALSE_START` is TX-33's paragraph; F1's vocabulary takes a word row's keys |

**TX-S3** ran once on the Debug app (Apple M2 Max, OS build 25F80, on AC; `rule_sha256`
`bede33d2…c5a0` matched): **E0**. On fixture (1), 20 boundaries, clipped onsets E0 0, E1 3, E2
at G 0/32/64/96 ms 10/3/3/3 (the clamp to the previous word's corrected end put three onsets
46–100 ms late whatever G); on o2 E2 placed only 4 of 58 edges from a run, 75 % of them in
non-speech at G ≥ 32 ms, under the rule's 95 %. E0 put 13 of the 20 edges inside the previous
phrase's audio, by 24–316 ms: recorded in TX-30 and JOB-11, and owed as an issue (the notes' "To file"). S-TH1 and S-RT1 do not
exist yet: skipped by name; TX-S3 re-runs when they land. Two runs before the recorded one
matched each boundary's word wrongly (by position, then by end): words tile the audio, so the
run that counts finds it by spelling (the spike's header says why).

**Measured.**

- `make typecheck`: exit 0, 0 errors, the 4 baseline warnings; `swift_build.py typecheck
  --define FRAMEJOB_DEV_TOOLS tools/proof/transcript_cut_probe.swift`: exit 0.
- `assistant_prompt_proof.py --probe`: 14/14 (F6: system 3219/6000).
- `spec_index_proof.py`: 234/234.
- `transcript_cut_proof.py` on Debug, then once on Release after the gate: "scores: 18/18"
  (U0–U6, Z0, C1–C9, C4b). C1: 20/20 boundaries, no clipped onset, 13 edges inside the previous
  phrase reported (−51 to −343 ms, snapped); C2 the three words one at a time and together both
  `[(0, 0, 1680000), (1680000, 2540000, 1380000)]`; C6 peak 4,097 refused with that N and 4,095
  clips kept, then peak 4,096 applied to 4,095 clips = `clips_after`; C7 `undo` named "Delete
  Words"; C8 2,163,200 bytes of PCM equal.
- The gate: `make gate` once, after the code and the documents: "gate: PASS 401s" — names 1 s,
  typecheck 6 s, fmt and lint skipped (no Rust), test 238 s, app 155 s; once more after T4's
  update and this record: "gate: PASS 87s" (names and test ran, the rest skipped).
  `name_residue.py` was re-run over this line.
- On Release after the gate, the proofs the change can move: `transcript_tab_proof.py` 21/22 on
  its first run — T4 wanted a click's selection to be `[7, 7]`, and TX-31 now plans a click,
  here widened to `[6, 7]` over the other track's word 6 it cuts into; the row was updated to
  want the plan's selection with 7 inside (TX-31), and T2 and T4 re-run: 2/2 (T2 compares the
  tab's tokens, cut keys included, with the tool's words: equal). `timeline_transcript_proof.py`
  33/33; `transcript_proof.py` 23/23 (A2: TX-33's paragraph verbatim). A Release instance
  launched by `proof_app.py launch --app release`: `grep "Frame Job: "` printed nothing.
- The ten mutants, once, on Release (`--mutants`): every one caught — `guard-0` and
  `fallback-no-lead` (U1), `no-cap` (U2), `snap-apart` (U6), `no-widening` (U3),
  `no-locked-refusal` (U4), `no-ceiling`, `after-no-spanning` and `ceiling-on-after` (U5), and
  `no-replan` (C9: the range stayed at the old cut after B's ripple delete; its tree copy built
  by `make app` in 182 s).

**Deviations, each recorded in TX-30…TX-33.**

- **TX-S3's verdict E0**, not E2, so `TranscriptCut.shipped` is `.e0`; E1 and E2 stay in the
  code for the spike's re-run on S-TH1 and S-RT1, and the probe drives them (U1).
- **Snapping keeps word starts on their side** (TX-30's new bullet): nearest frame, but a start
  never past the first cut word's start and an end never past the next shown word's start (their
  frame floors). The spec had the core's nearest snap alone; C2 failed with it on real words —
  a start rounded past "gulls" left a 4,000-tick sliver of it in the transcript, and the next
  Delete left a one-frame clip — because TX-10 places a word in the clip holding its start.
- **Widening reads a word's onset, not its corrected start**, against the unsnapped cut (TX-32):
  under E2 the clamp makes the next word's onset its start or later, so a corrected-start extent
  would add it and then every word after it.
- **The probe catches mutants 1–9** (U1–U6), not C6: the same functions C1–C6 drive, without
  three Release builds of a tree copy; `no-replan` builds one and runs C9.
- C1 scores the verdict's own claim (no clipped onset); "every edge in the silence" is false
  under E0 by TX-S3's numbers, so C1 reports those edges and does not score them.
- `TranscriptCut.swift` came before the decisions (TX2a's precedent), since TX-S3 measures it.

**What CP1 needs from the owner** (after TX3b lands, in the build with both):

1. Copy the T1 recording (S-TH1, the GH5 talking head and its RØDE file) and the retake read
   (S-RT1) to `tools/proof/media/creator/S-TH1/` and `S-RT1/`, so TX-S3 and JOB-11 can run on
   real speech.
2. Open T1 in a new project, choose View ▸ Transcript (⌃⌘T) and wait for the words.
3. Cut T1 to a state you would publish by deleting words in the tab: select (click, drag,
   ⇧-click), listen to the shaded range with Loop, press ⌫; undo what sounds wrong.
4. Note, in CJ-5's form: each time you left for another tool or gave up, and why; each slow
   step; each cut that sounded wrong, with its time (a clipped start, a fragment left, an
   unnatural pause, the end of the word before eaten — TX-S3's E0 risk); and what you want
   from TX4–TX7 that the plan does not give.
5. Run JOB-11 (`docs/manual-checks.md`) on the same recording.

TX4 does not start until that record is in.

**Reviews.** Review 1 (`ef2ccde5..92535447`, fix-required): one should-fix and two nits. The
should-fix: `docs/guide/transcript.md`'s "Other tracks" bullet said a word on another track that
overlaps the selection is always added, false when that word starts inside the last selected
word — it is then the next shown token, so `Table.cut` ends at its onset and the rest of the
deleted word can stay. Fix pass 1 (`338e6163`, documents only) wrote the bullet from `widen` and
`Table.cut`; `make gate` "gate: PASS 300s" (names and test ran, the rest skipped); no code or
instrument changed, so the Release proofs and the mutants were not re-run. Review 2
(`ef2ccde5..338e6163`): pass, with review 1's two nits left as they stand: a widened drag
re-plans and calls `transcriptSetRange` on every `mouseDragged` event even when the range has not
changed (`TranscriptView+Delete.swift`); and `get_timeline_transcript` and `cutTable()` read each
media's voice cache, which the shipped rule E0 never uses.

**Integration (2026-11-02).** Cherry-picked (`92535447`, `338e6163`) onto the integration branch
after CO1 and CO2a1 (format 39), with no format change of its own. Conflicts only in the indexes,
the decision file and two documents, each kept both. `creator-jobs-3.md` held CO1's and CO2a1's
blocks at 485 lines, so TX3a's paragraph and TX-30…TX-33 would have made it 595, past the series'
~500-line rule: they moved to a new `11-decisions/creator-jobs-4.md` (121 lines), which its own
index row and the four TX-30…TX-33 rows link; TX-23's Amended line by TX-31 stays with TX-23 in
`creator-jobs-3.md` (490), whose head and Holds cell now say the series goes on in
`creator-jobs-4.md`, as do `creator-jobs.md`'s head and this file's. `docs/guide/mcp.md` keeps
TX3a's `get_timeline_transcript` row and CO1's `get_media_analysis` row; `tools/proof/README.md`
keeps CO2a1's section and then TX3a's; the spec README's 07.9f row is TX3a's and its
`11-decisions/` total is 18385 in 38 files (`spec_index_proof.py` 240/240). Every `app/Sources`
file and instrument TX3a changed is the lane's byte for byte (CO1 and CO2a1 touched none of
them), so the lane's Release runs stand: cut 18/18, mutants 10/10, tab 21/22 then T2/T4 2/2, TX1
33/33, transcript 23/23, and the empty parity grep. The `CLAUDE.md` edits owed went in:
`app/CLAUDE.md`'s Transcript-tab entry names `TranscriptCut.swift` (+`Plan`) and
`TranscriptView+Delete.swift` and gains TX3a's paragraph (the pure cut and plan, `TranscriptHost`'s
range and Delete Words, the pane's planning and `rangeSet`, `cutTable()`); the editor entry says
`+Timeline`'s delete family forwards to the pane first and both validator arms answer true; the
`TimelineTranscript.swift` entry says the tool's rows carry `cut_start`/`cut_end`. `make gate` on
the merged tree: names, typecheck (the four baseline warnings), test and app `pass` (fmt and lint
skipped, no Rust changed), "gate: PASS 291s"; a Release instance of that build launched by
`proof_app.py launch --app release`: `grep "Frame Job: "` printed nothing.

**Owed.** JOB-11 (a person, `docs/manual-checks.md`) on S-TH1, and TX-S3's re-run on S-TH1 and
S-RT1 once they are copied (CP1's step 1 above); TX3b, the pause token (TX-34), is the next
pipeline, not an issue. Filed after the commit: "TX-S3: E0's cut edges fall inside the previous
word on the `say` fixture (13 of 20)".

### CU2 — the core evaluates a cursor file

- **What a person gets:** nothing visible: the arithmetic CU3a draws with, and the path VR5 reads.
- **Core:** `cursor_track.rs` (the loaded file; global points to movie pixels by CU-S2's mapping per
  geometry change; sample times to source ticks); `cursor_smooth.rs` (smoothing pinned at every
  click, simplified with a tolerance growing with `smoothing`, drawn as a centripetal Catmull–Rom
  spline in time; `smoothing` 0 is the raw samples linearly interpolated with no precompute;
  non-causal, so the smoothed cursor never lags a click; computed by a `prepare` request once per
  track and smoothing value and kept in the handle under its lock; a `state` at an unprepared
  smoothing answers the raw path, never computes one); idle hide (hidden after `hide_idle` s without
  movement with a 0.2 s fade, shown 0.15 s BEFORE the next movement, hidden through a recorded
  `hidden` span); ripples (each down click's ring phase over 0.45 s); `cursor_query.rs` (the request
  vocabulary: `prepare {smoothing}`; `state {at, props}` answering visible, x, y in movie pixels,
  the image id and its size at `scale`, opacity, the active ripples, and — CU11 — the positions at
  the shutter's two ends; `image {id}`; `events {from, to, kinds}` (clicks, scrolls, shortcuts,
  typing stretches); `path {from, to, step, smoothing}`, the smoothed position in source time at
  most 10 Hz, which VR5 reads; later `plan_zooms`, `plan_overlays`, `plan_typing`).
  `core/tests/cursor_track.rs` over hand-written fixtures with known answers.
- **FFI:** `rc_cursor_query(tracks, n, project, request_json, err_out) → char *`, pure; header and
  wrapper within CU1a's room (CU-9).
- **Swift:** `ReelCursor.query`; typed answers in `CursorValues.swift`; `CursorTracks.swift`, a
  process-wide registry of open tracks keyed by path, size and modification second (LRU, small):
  loading and preparing happen off main and off the compositor's thread on a utility queue
  (`RecipeSource.set` and `Playback.update` ask for each cursor media at each clip's smoothing); the
  compositor's `ready(path:smoothing:)` never blocks; a landing posts `.cursorTrackDidLand`;
  `wait(paths:smoothings:)` is the export's; `-RCDevCursorLoadHold <s>` (dev only) holds each load.
  No drawing yet.
- **MCP:** none.
- **Docs:** spec §7.1 (the export and its vocabulary), §7.10; `core/CLAUDE.md`, `app/CLAUDE.md`;
  root `CLAUDE.md`'s dev launch defaults (`-RCDevCursorLoadHold`).
- **Decisions (draft):** **CU-20** the mapping (CU-S2). **CU-21** smoothing's definition, its pin at
  clicks and its precompute by `prepare`. **CU-22** idle hide's lead and `hidden` spans. **CU-23**
  ripple timing. **CU-24** a file newer than the core is refused by name and the clip draws without
  a cursor. **CU-25** the request vocabulary, the `path` request VR reads, and that the compositor
  never opens a file or prepares a path.
- **Acceptance:** `cargo test --release --test cursor_track`; the state at every fixture time equals
  its hand-computed answer; CU-S4's speed holds through the FFI.
- **Proof rows:** T1 (granted; skipped by name) the core's mapping against K1's recordings ≤ 1.5 px
  p95; T2 `state` ≤ 20 µs median through `rc_cursor_query` on the one-hour fixture, and `prepare`
  inside CU-S4's bound; T3 (probe) with `-RCDevCursorLoadHold 2`, `ready` answers nothing at once
  and the track after the hold, the landing posting once; T4 `path` at 10 Hz equals the
  hand-computed smoothed positions.
- **Mutants** (7): the click pin dropped; the tolerance not scaled; the idle lead 0; geometry read
  from the first change only; the newer-version refusal removed; `state` preparing on demand (T2's
  time); `ready` blocking on a load (T3).
- **Depends on:** CU1a (CU1b for T1's data). **Lane** B.

#### CU2's record (2026-11-01)

**Landed.** Lane B, base `eb350b86` (I's HEAD). One decisions commit (`ce498633`: CU-20…CU-26
and their index rows), then one commit with the code, the probe and the documents; landed on
`worktree-creator-jobs` as one commit. Nothing a person or an agent sees changed: no tool,
catalog, menu, recorder file or format version moved, so the parity check is untouched.
`RecipeSource.set` and `Playback.update` are not wired to `CursorTracks` yet (CU-26: CU3a2,
when the recipe carries cursor media; no media has a cursor before CU3a1). A deviation from the
spec's first CU-26 text, which capped "unpinned" paths and smoothings: both caps count every held
entry, pinned ones included, and only unpinned ones are evicted (T5 (b) needs it); CU-26 was
amended in the fix pass to say so. The fix pass also moved `want`'s and `release`'s queueing of
prepares and `unprepare`s inside the lock, so the queue's order follows the lock's (review
finding 1: a concurrent `want` could otherwise land a smoothing whose late `unprepare` then ran).
After it: `make typecheck` the 4 baseline warnings, `cursor_track_probe.py` 5/5 (T1 skip) on
Debug, `make gate` PASS 445 s, and `RC_PROOF_APP=release` `cursor_track_probe.py` 5/5 (T1 skip).

| File | Lines | What |
|---|---|---|
| `core/src/cursor_track.rs` | 283 | `CursorTrack` (the handle: the file, the down clicks, the prepared paths under a `Mutex`), ticks ↔ µs, the constants, CU-20's M1 mapping (`to_movie`, the one function), the raw path, idle opacity, the image in force, ripples |
| `core/src/cursor_smooth.rs` | 226 | `hold_end` (the one hold rule), `SmoothPath` (pins, RDP with an explicit stack, centripetal Catmull–Rom by Barry–Goldman) |
| `core/src/cursor_query.rs` | 365 | the request vocabulary (its module doc), `query`, every refusal |
| `core/src/cursor_bursts.rs` | 25 | `typing_stretches` |
| `core/src/cursor_file_check.rs` | 357 | `encode_base64` beside `decode_base64` |
| `core/src/ffi_cursor.rs` | 102 | `rc_cursor_open` / `rc_cursor_free` over `CursorTrack`, `rc_cursor_query` |
| `app/Sources/ReelCore+Cursor.swift` | 45 | `ReelCursor.query` |
| `app/Sources/CursorValues.swift` | 331 | `CursorStateProps`, `CursorState`, `CursorImage`, `CursorEventKind`, `CursorEvents`, `CursorPath`, the typed `ReelCursor` requests; `CursorKind` `Codable` |
| `app/Sources/CursorTracks.swift` | 280 | the registry, `.cursorTrackDidLand`, `-RCDevCursorLoadHold` |
| `core/tests/cursor_track.rs` | 595 | 15 tests through `rc_cursor_open` / `rc_cursor_query` |
| `tools/proof/cursor_track_probe.swift` · `.py` | 307 · 180 | B0, T1 (skipped by name), T2–T5 and two mutants |

**Measured.**

- `cargo test --release --test cursor_track`: 15 passed — each decision's numbers at fixture
  times (linear and collinear-uniform answers to 1e-9 px; a two-pin smoothed segment to its
  smoothstep within 1e-5 px, the knot floor's share), a continuous run's pinned ends at 0.5,
  `unprepare` answering true and `state` then raw, every refusal, a v2 body with only v1 keys
  refused "…is version 2…" through `rc_cursor_open`. `--test cursor_file` 12 passed;
  `--test model_tests null_safety` 1 passed with `rc_cursor_query` in the sweep.
- `cargo fmt`, `make lint` clean; `make typecheck` 0 errors and the 4 baseline warnings.
- Core mutants, each run once and reverted byte-identical (SHA-256 checked), all caught: click
  pin dropped; tolerance not scaled; idle lead 0; geometry from the first entry only; the
  newer-version refusal removed; `state` preparing on demand (the unprepared-is-raw test; T2
  times a non-storing core only, so this mutant is the core test's); dwell hold dropped; ripple
  window 0.5 s.
- `cursor_track_probe.py` (Debug-shaped build): T1 skip, T2–T5 pass, 5/5 — `state` medians
  4.46 / 4.25 µs prepared and 4.21 / 4.04 µs unprepared, `prepare` at 1 0.012 / 0.011 s; T3
  `ready` 0.009 ms, the track after 2.15 s, one landing. Mutants `ready-blocks` (T3: `ready`
  took 2011.1 ms) and `evict-pinned` (T5: 8 of 10 ready, `wait` cancelled) caught.
- `cursor_capture_probe.py`: 7/7.
- `make gate`: PASS 606 s (names 1, typecheck 8, fmt 9, lint 17, test 382, app 189).
- Release (`RC_PROOF_APP=release`, the probe built `-O`): `cursor_track_probe.py` 5/5, T1 skip —
  `state` medians 4.25 / 3.83 µs prepared and 3.75 / 3.67 µs unprepared, `prepare` at 1 0.030 /
  0.013 s, T3 the track after 2.15 s; `cursor_capture_probe.py` 7/7. Three lanes shared the
  machine; each timing is one run of two.
- After the fix pass: Release `cursor_track_probe.py` 5/5 (T1 skip), `state` medians 4.29 /
  4.00 µs prepared and 3.71 / 3.83 µs unprepared, T3 the track after 2.14 s;
  `spec_index_proof.py` 225/225.

**Review.** Review 1 found two should-fix items, both fixed in one pass (`95fd0ff7`): the
queueing race above, and CU-26's text, which still capped only unpinned entries. Review 2
passed with three nits left as nits: `CursorTracks`' class doc still words the caps as
unpinned-only; `wait` calls `cancelled()` while holding the lock, so a closure that reads
`ready` or `failure` would deadlock; and `perform`'s `try? prepare` lands a smoothing the core
refused as `ready`. The CLAUDE.md map entries (`core/CLAUDE.md`'s cursor modules,
`app/CLAUDE.md`'s `ReelCursor.query` and `CursorTracks.swift`, the root's
`-RCDevCursorLoadHold`) were applied when the phase landed.

**Owed.** T1 (the mapping against K1's granted recordings) waits for CU1b's recordings, and
CU-S2's verdict (JOB-29) may amend CU-20's mapping function.

### CO2a — Remove Background in the model, then drawn

CO2a is two pipelines (CJ-7's re-split): CO2a1 puts the cutout in the model, the plan and the
recipe, readable by agents and byte-identical for every project without one; CO2a2 draws it. "CO2a"
in a dependency means both. They share CO-20…CO-29.

- **Decisions (draft):**
  - **CO-20 — `video.cutout`** (format p): `null`, or `{subject, quality, background, edge,
    feather}`. `subject` `person` (CO10 adds `foreground`); `quality` `standard` or `best` (only
    `standard` if CO-S1 found no Best); `background` `remove` (the layer draws the subject alone) or
    `keep` (the layer draws whole; its subject still hides Behind Subject clips, CO-50); `edge` −1…1
    shrinks or grows the outline; `feather` 0…1. Written only when set. Refused, each in its own
    sentence, on a text, shape, graphic, adjustment, nest or image clip (images until CO10).
    `subject`, `quality` and the key's presence are BASE-only: `set_action_end` refuses
    `video.cutout`, `.subject` and `.quality` by name in `not_a_target` (as `video.motion`), and the
    evaluator restores the base values (R5-4's mechanism); `edge`, `feather` and `background`
    animate by §5.4's object rule.
  - **CO-21 — The recipe's `cutout` key (no mask track: CO-3 as CO0 rewrote it).** The plan
    gains nothing: a cutout adds no composition track, no segment and no decoder. The recipe
    layer's key after `dissolve` (and CU3a1's `cursor`, by landing order) is `cutout`: `null` or
    `{mask, background, edge, feather}`, `mask` carrying what CO-3's pack lookup needs — at least
    `{kind: "media", media, quality}`, the media whose pack holds the masks (CO10 adds `{kind:
    "image", media}`); the rest of its shape is settled at CO2a1's head. The integrator renumbers
    `recipe_layer.rs`' doc by landing order.

#### CO2a1 — the cutout in the model and the recipe

- **What a person gets:** nothing drawn yet. Agents set `video.cutout` with `set_video` and read it
  back through `get_project`; the recipe carries the `cutout` key that CO2a2 draws; a clip with a
  cutout still draws uncut, as CO-6 says a clip without its masks does. The plan is unchanged.
- **Tolls first:** `edit_action.rs`'s end-patch door (99–290) → `edit_action_end.rs`;
  `AgentCatalog+Properties.swift`'s video patch (23–191) → `AgentCatalog+VideoPatch.swift`;
  `actions.rs` and `format_history.rs` only if this phase's wiring would pass their marks.
- **Core:** `model_cutout.rs` (`Cutout`, `CutoutSubject`, `CutoutQuality`, `CutoutBackground`; the
  field `VideoProps.cutout` in `model_props.rs`, after `look`); `cutout_check.rs` (`check_cutout`,
  one call from `props_check.rs`); `edit_action_end.rs` (the base-only refusals); `actions.rs` (the
  base restore beside `motion`'s); `recipe_layer.rs` (`cutout`, with what CO-3's lookup needs), one
  call in `recipe.rs`; the format bump (`format.rs`, the header's `#define`, `format_history.rs`,
  `core/tests/schema_vN.rs`) and `core/tests/cutout.rs` (the refusals, the base restore, the
  recipe's `cutout` key on a trimmed, ×0.5, ×2, ×1.37, ramped, frozen, reversed, split, nested and
  cross-dissolved clip, and a project without a cutout planning and recipe-ing byte-identically).
- **FFI:** the bump's `#define` only.
- **Swift:** `VideoProps.swift` (`CutoutProps`); `TypedPatches.swift`, `OpDictionaries.swift`
  (`VideoPatch.cutout`); `FrameRecipe.swift` (`RecipeLayer.cutout` decoded, not yet drawn).
- **MCP mirror:** `set_video`'s description and `videoPatchDescription` name `cutout`; the gate and
  parity see it through the op table; `get_project` shows it.
- **Docs:** spec §5.2a (`video.cutout`), §6 (`set_video`), §7.3 (`cutout`); `core/CLAUDE.md`
  (`model_cutout.rs`, `cutout_check.rs`, `edit_action_end.rs`, the layer's key count);
  `app/CLAUDE.md` (the snapshot and recipe fields).
- **Acceptance:** core tests; a project without a cutout plans, recipes and exports byte-identically
  to before the phase; the proof rows against Release; `make gate`.
- **Proof** (`co2a_proof.py`'s first rows, Release): D8 refusals — `cutout` on a text clip,
  `video.cutout.quality` in an action end, `edge` 2 — each in its sentence; D10 golden frames of the
  existing fixtures unchanged; D13 `set_video {cutout}` read back through `get_project`, and the
  layer's recipe `cutout` key naming the clip's media (`frame_recipe` through a probe); D14 a
  cut-out clip draws byte-identical to cutout off until CO2a2.
- **Mutants** (3): `subject` accepted in an action end (D8); the recipe's `cutout` key naming
  another media (D13); the cutout written when `null` (D10).
- **Manual checks:** none. **Depends on:** CO0, CJ0b (T3), CJ0d (T11, T14). **Lane** C.

#### CO2a1's record (2026-11-02)

**Landed.** Lane C, base `33bfb571` (I's HEAD, CO1; the harness made the worktree at `eb350b86`
and it was fast-forwarded to `33bfb571` before any edit, nothing of its own on it). Four
commits: the decisions (`ae3a802e`: CO-20, CO-21 and CO-23 with their index rows), the toll
(`34d20441`), the code, the proof and the documents (`9cb9a428`), then this record
(`abf48c0a`), cherry-picked onto `worktree-creator-jobs` as one commit. Format 39 landed as
numbered: no other phase had taken it. Nothing is drawn: an agent sets
`video.cutout` through `set_video` and reads it through `get_project`; every layer carries
`"cutout": null` unless a media or still clip's media is in the project and its evaluated cutout
is set, when it is `{mask: {kind: "media", media, quality}, background, edge, feather}` naming
the clip's own media.

- **No deviation from the spec.** The owner's CO2a answer is CO-15's; CO2a1 adds none.
- **The toll paid here:** `edit_action.rs`'s end-patch door (lines 99–290, `prune_removed`
  through `key_off`) to `edit_action_end.rs`, a pure move gated alone (`cargo fmt --check` and
  `cargo test --release` in `core/`, `make lint`; the moved lines differ from the base only in
  six widened `fn`/`struct` lines; `grep -c "Some(slot) => (object_at(fields, path.key),
  slot)," core/src/edit_action_end.rs` 1); 595 → 402 lines. `audio_ap8b_proof.py`'s M13 names
  the new file. `actions.rs` took one line (588, under 590), so no `actions_json.rs` toll;
  `format_history.rs` is 383. Spec §7.3 (497) paid its split: the `**Recipe options**`
  paragraph to its end moved whole to `07.3b-frame-recipe-options.md`.
- **CO-20's split and freeze:** neither needed an edit. Both read the evaluated state, which
  `restore_base_cutout` already holds to the base; `core/tests/cutout.rs` checks both halves of
  a split and a freeze's still name their media and keep the cutout.

| File | Lines | What |
|---|---|---|
| `core/src/model_cutout.rs` | 76 | `Cutout`, `CutoutSubject`, `CutoutQuality`, `CutoutBackground` and the ranges |
| `core/src/cutout_check.rs` | 105 | `check_cutout`, `check_cutout_clip`, `clamp_cutout`, `restore_base_cutout` |
| `core/src/edit_action_end.rs` | 233 | the toll's door, `not_a_target`'s `video.cutout` arm and `check_cutout_end` |
| `core/src/recipe_layer.rs` | 202 | `Project::layer_cutout`, the layer's 28th key |
| `core/tests/cutout.rs` · `schema_v39.rs` | 498 · 118 | 10 and 5 tests |
| `app/Sources/CutoutProps.swift` | 109 | the mirrors: `CutoutSubject`, `CutoutQuality`, `CutoutBackground`, `CutoutProps`, `RecipeCutoutMaskKind`, `RecipeCutoutMask`, `RecipeCutout` |
| `app/Sources/AgentCatalog+VideoPatch.swift` | 220 | `cutoutClause` |
| `tools/proof/co2a_proof.py` · `co2a_probe.swift` | 397 · 160 | B0, D13p (probe), D8, D10, D13, D14, Z1 (app) |

**Measured.**

- `cargo test --release` in `core/`: `cutout` 10 passed (`{}` storing the five defaults, a
  merge, `null` removing, `{}` again an identity; every sentence, each clip kind through
  `set_video` and the text clip through `paste_attributes`; the end refusals with a `null` and
  `off`, and `edge`, `feather`, `background` taken; hand-written ends — `quality` and
  `cutout: null` restored to the base, an end cutout on a base without one `null`, edge 0 → 1
  at 0.5 mid-action, feather 0.25, edge 5 clamped to 1, feather −3 to 0, `background`
  switching only at the end; the key through a trim, ×0.5, ×2, ×1.37, `add_speed_ramp`,
  `freeze_frame`, a reverse, `split` (both halves), a nest and a cross-dissolve (both halves
  inside the overlap), each naming its own media of 5 and 7; `null` on a hand-written text
  clip and the burn-in; `add_blurred_background`'s copy with no `video.cutout` and a `null`
  key, clip 11's unchanged; a cutout-less project and the same with a cutout: `plan_text()`
  equal, recipes equal with every `cutout` removed at four times, no `"cutout"` in the saved
  text). `schema_v39` 5, `background` 42, `schema_v38` 5, `recipe` 15 (`LAYER_KEYS` 28),
  `action_off` 13, `patch_door` 9, `cursor_recipe` 13, `edit_tests` 53, `model_tests` 31
  passed.
- `cargo fmt --check`, `make lint` clean; `make typecheck` exit 0 with the 4 baseline
  warnings; `swift_build.py typecheck tools/proof/co2a_probe.swift` exit 0;
  `spec_index_proof.py` 237/237; `name_residue.py` exit 0.
- `co2a_proof.py --only B0,D13p` 2/2; on Debug (`make app-debug`) all rows passed (6/7 on the
  first run, D8's text clip placed on the media clip's span and refused by the overlap rule;
  moved to 11 s, `--only D8` 2/2).
- Mutants, each run once and reverted byte-identical (SHA-256 checked), all caught: M1
  `check_cutout_end` without its `subject` test (`cutout`'s end-refusal test); M2
  `layer_cutout` writing the clip id as `media` (five `cutout` tests, and D13p after `make
  rust`: media 11 and 12); M3 `skip_serializing_if` off `VideoProps.cutout` (`schema_v39`'s
  v38 text test); M4 `cutout: None` out of `add_blurred_background`'s literal (`cutout`'s
  blurred-copy test).
- `make gate`: PASS 467 s (names 1, typecheck 7, fmt 3, lint 7, test 268, app 180).
  `RC_PROOF_APP=release co2a_proof.py`: 7/7 — D10 reads the version-38 fixture through this
  build at 39 (every key equal, no `cutout`), three frames, and after a save to a new package
  and a reopen `get_project` equal and the three PNGs byte-identical; D14's three frames with
  a cutout equal the uncut ones; no older build is driven.
- Integration: the cherry-pick onto `33bfb571` applied with no conflict; `make gate` on the
  integrated tree, with the two review nits and the CLAUDE.md entries: PASS 470 s (names 1,
  typecheck 8, fmt 3, lint 13, test 283, app 161).

**Review.** Verdict pass, every Files and Approach item done; two nits, both applied at
integration as doc comments: `check_off`'s refusal order (`edit_action_end.rs`) now names
`video.cutout` beside `video.motion` and `text.words`, and `set_action_end`'s doc
(`edit_action.rs`) names `check_cutout_end`'s `subject`/`quality` refusal (CO-20). The
CLAUDE.md map entries were applied at integration: `core/CLAUDE.md`'s `model_cutout.rs` ·
`cutout_check.rs` and `edit_action_end.rs` entries (the door out of `edit_action.rs`'s) and
"twenty-eight keys"; `app/CLAUDE.md`'s `CutoutProps.swift` and `RecipeLayer.cutout`.

**Owed.** No manual check and nothing to file. Drawing is CO2a2's.

#### CO2a2 — the mask drawn

- **What a person gets:** a clip with `video.cutout` draws only the person wherever its masks are
  cached, in the preview, `render_frame` and every export, and draws uncut where they are not.
  Agents make masks with `get_media_analysis`; CO2b makes them on demand, CO3 adds the inspector.
- **Swift:** new `Compositor+Cutout.swift` (CO-3's per-request lookup: the composition time through
  the covering picture segment's linear map in ticks to the source time shown, the source frame
  shown there (the last at or before it), and the mask of its nearest analysed frame, ties to the
  earlier, from the media's forward pack — a reversed segment's times mirrored by `T − end`, the
  forward pack read mirrored, never a second file; CO-5's window rule; the mask's bytes uploaded as
  stored, never through AVFoundation or step 0); `MaskPack` read mapped and kept per path and
  marker; `LayerUniforms.swift`, `Compositor+Uniforms.swift` (CO-8's group); `Compositor.metal`
  (`texture(4)` sampled at display-space `uv` before `orientedUV`, the step-7 multiply with r0's
  remap); `CompositorEffects.swift`, `Compositor+Shadow.swift`, `Compositor+Dissolve.swift`,
  `Compositor+Matte.swift` (bind the mask or the placeholder). The composition, its track ids, its
  instructions and `ReverseCache` are what they are without a cutout. The proofs pinning the
  uniform size move to CO-8's figure: `phase8_chrome.py:3248–3255`, `tone_probe.swift:72–74`,
  `look_probe.swift:56–58`, `wheels_probe.swift:76–78`, `curves_probe.swift:338–341`,
  `hdr_probe.swift:1090, 1103`, and the prose of `tone_proof.py:71`, `wheels_proof.py:76–77`,
  `look_proof.py:83`, `hdr_proof.py:305`.
- **MCP mirror:** `render_frame` draws it; no new tool.
- **Docs:** spec §7.5b (`texture(4)`, step 7, the pack lookup, the step-0 bypass); `app/CLAUDE.md`
  (the compositor's pack lookup, the uniform block's size); `docs/manual-checks.md` (JOB-61).
- **Acceptance:** proof rows against Release; a project without a cutout renders and exports
  byte-identically to before the phase; `make gate`.
- **Proof** (`co2a_proof.py`'s drawing rows, Release; canned `masks` packs (CJ-26) carrying CO-S2's
  bar code, and a real person fixture's pack from `get_media_analysis`): D1 registration — the cut
  layer's alpha shows the nearest analysed frame's mask through a trim, ×0.5, ×2, ×1.37, a ramp, a
  freeze, a reverse, a split, a nest and a cross-dissolve, at every frame and at a capped rate; D2
  on the person fixture, where the bilinear footprint lies in a 3×3 mask-texel neighbourhood all 0
  the frame equals the clip hidden byte for byte, and where all 255 the uncut picture; D3 a cut-out
  clip with no pack in the store draws byte-identical to cutout off; D4 the no-person UI fixture
  draws uncut (CO-5); D6 the drop shadow's alpha follows the outline; D7 on a transparent canvas the
  clip's coverage in an HLG project equals the SDR project's within 1/255; D11 a freeze frame of a
  cut-out clip draws its held frame's mask; D12 a portrait-tagged bar-code clip registers and its
  mask lies upright; D16 (CO1's M10, moved here with CO-3's mirror) a reversed clip's frame k draws
  the forward pack's mask at the mirrored time, `T − end`.
- **Mutants** (8): the mask sampled through `orientedUV` (D12); the mask one frame late (D1); the
  lookup rounding the source time instead of taking the frame shown (D1's ×1.37); a missing mask
  drawing transparent (D3); the shadow pass binding the placeholder (D6); CO-5 judged per analysed
  range (D4); the mask through step 0 (D7); the mirror's pivot one frame off (D16).
- **Manual check:** **JOB-61** — a cut-out 1080p camera over a 4K screen recording plays smoothly on
  the owner's Mac.
- **Depends on:** CO2a1, CO1, CJ0c (T6). **Lane** C. **Questions:** none expected.

#### CO2a2's record (2026-11-02)

**Landed.** Lane C, base `f82c5b20` (I's HEAD, TX3; the harness made the worktree at `eb350b86`
and it was fast-forwarded to `f82c5b20` before any edit, nothing of its own on it). Commits: the
decisions alone (CO-24…CO-29 with their index rows), then the code, the proof and the documents,
then this record. No format bump, no `rc_*`, no core change. A clip whose recipe `cutout` has
`background` remove draws only the person wherever its media's mask pack covers the frame shown —
in the preview, `render_frame` and every export, through the one compositor — and uncut wherever
it does not; a project without a cutout renders and exports byte-identically to the base (D15).

| File | Lines | What |
|---|---|---|
| `app/Sources/CutoutLookup.swift` | 164 | `CutoutPlan` (a handle's segments per track, reversed pivots, clip windows) and `CutoutLookup` (`sourceTick`, `ends`, `slot`, `subjectFound`), pure |
| `app/Sources/CutoutMasks.swift` | 200 | `CutoutPack` and `CutoutMasks`: plans per key against a weak handle, packs per (cache folder, media) re-read on the marker's stat, stamps, found windows, an LRU of eight `r8Unorm` textures |
| `app/Sources/Compositor+Cutout.swift` | 49 | `MetalRenderer.cutoutMask`: the group filled and `texture(4)` answered, the placeholder on any miss |
| `app/Resources/Shaders/Compositor.metal` | — | the cutout group, `cutoutCover`, `texture(4)` on both layer fragments, step 7b's multiply |
| `LayerUniforms.swift` · `CompositorEffects.swift` · `Compositor+Dissolve.swift` · `Compositor+Shadow.swift` · `Compositor+Uniforms.swift` · `MetalRenderer.swift` | 368 · 473 · 214 · 299 · — · 378 | the group (160 floats, 640 bytes), `PreparedLayer.cutout`, the bindings, `partnerBox`'s cutout clause |

- **Deviations from the spec.**
  - `CutoutMasks.pack` takes `urls` beside the media's URL, and its stamp key carries the LUT's
    URL: `ThumbnailInput(media:urls:)` reads a LUT Camera Log's file from the map, so the stamp
    `ProjectDocument.analysisRequest` makes cannot be made from the media's URL alone.
  - The bar-code movie is CO-S2's writer (`mask_track_writer.swift`'s `writeBarcode`) run through
    `co2a_probe`'s `barcode` mode for 300 frames, not `cutout_spike.barcode_fixtures()`, which also
    writes `barcode_rev` and an hour of `long_60m` this phase has no use for.
  - D2's uncut class is every pixel over a 3 × 3 neighbourhood of texels ≥ 192 rather than = 255:
    the push-in's person never reaches 255 (its masks top out at 246, as CO-S1 found), and r0's
    remap at edge 0 is exactly 1 for any m ≥ 0.75. D2's times are 1.5, 1.667 and 1.9 s, where the
    push-in's masks hold more than 6,000 such pixels (at 0.5 s and 1 s they hold none).
  - D1 scores the cross-dissolve's incoming codes after the overlap: inside it the incoming's alpha
    band is `p` × the mask over the outgoing's `1 − p`, too faint to read at small p.
  - D11 and D16 are read from D1's freeze and reverse frames, not separate renders.
  - The `mask-lifted` mutant changes the mask's value in an HLG project only (`pow(m, 0.8)`), a
    stand-in for a lift through step 0, which an `r8Unorm` mask cannot take.

**Measured.**

- `make typecheck` exit 0 with the 4 baseline warnings; the shader compiles with the base's two
  warnings (`kTransitionNone`, `kMatteNone`); `swift_build.py typecheck` of the probe exit 0;
  `spec_index_proof.py` 240/240; `name_residue.py` exit 0.
- The five size pins on Debug: `tone_proof.py --only P3`, `wheels_proof.py --only P3`,
  `look_proof.py --only L3`, `curves_proof.py --only P13`, `hdr_proof.py --only P9`, each 1/1.
- `co2a_proof.py --only B0,D13p,D1p` 3/3 (3,060 lookup rows over 20 case × rate pairs).
- `co2a_proof.py` whole on Debug (`make app-debug`): 18/18, after three fixes to the instrument
  (D1's fixture ids clashing, its split asked at the freeze's rippled start, D2's uncut class
  above). D15's base Debug app built in 29 s.
- `make gate`: PASS 474 s (names 1, typecheck 7, fmt and lint skipped, test 297, app 168).
- `RC_PROOF_APP=release co2a_proof.py`: 18/18 — D1 every frame and 15/s, each case's every frame
  (trim 60, ×0.5 60, ×2 60, ×1.37 60, ramp 90, freeze 90, reverse 60, split 60, nest 60, the
  dissolve's incoming 30) and the dissolve's 30 overlap frames at round(255·(1 − p)) ±1; D2 at
  1.5 s, 1.667 s and 1.9 s: 147,385, 144,683 and 149,923 pixels over all-0 neighbourhoods equal to
  the clip hidden and 9,154, 11,430 and 6,232 over saturated ones equal to the uncut frame, none
  differing (masks 512 × 384); D3 both misses byte-identical to cutout off; D4's three frames
  byte-identical (no person, 60 frames analysed); D6 worst 0/255 over 137,261 pixels; D7 worst
  1/255 over 230,400 pixels (1,137 partial); D12 codes 15, 40, 75 upright; D15 three PNGs and 60
  frames' md5 equal to the base `f82c5b20`'s Release app (built in a tree copy in 174 s).
- Mutants, each once on Release in a tree copy (the tree's files untouched, SHA-256 checked
  before and after): all nine CAUGHT, each copy built in 157–162 s. `partner-box` D1 (the dissolve's outgoing alpha 255 through the overlap at both rates); `oriented-uv` D12 (neither code reads at any of the three frames); `one-frame-late` D1 (every case at both rates, the mask one frame behind the picture); `nearest-frame` D1 (×0.5, ×1.37, the ramp and the freeze at every frame, ×0.5, ×1.37 and the ramp at 15/s); `miss-transparent` D3 (both misses); `shadow-placeholder` D6 (worst 255/255); `co5-per-range` D4 (the three frames differ); `mask-lifted` D7 (worst 60/255); `pivot` D16 (all 60 reversed frames at every frame, 30 at 15/s, the mask one frame off).

**Review.** Verdict pass, no blocker or should-fix: every item of the spec done, deviations
reasoned; checked that `cutoutUV` registers under crop, lens and snap (D12), that no draw through
the layer fragments leaves `texture(4)` unbound, that `CutoutMasks` needs no lock (one renderer
per compositor, its serial render queue) and that the plan is decoded once per handle. One nit,
left as is: the found-window LRU (256) holds a superseded `CutoutPack` mapped until evicted after
a re-publish, although no lookup can hit it — the memory is mapped and bounded.

**Integration** (2026-11-02, onto `worktree-creator-jobs` after CJ5b): `creator-jobs-4.md` and the
two index files met CJ5b's CJ-51 and CJ-52 and were kept both, CJ5b's first (`creator-jobs-4.md`
278 lines, `11-decisions/` 18551 in 38 files; `spec_index_proof.py` 240/240). `app/CLAUDE.md`
took the four owed edits: the `FrameRecipe.swift` entry, the compositor's list with
`Compositor+Cutout.swift`, `CutoutMasks.swift` and `CutoutLookup.swift`, the uniform block's 160
floats and its cutout group, and the `texture(4)` sentence beside `texture(5)`'s.

**Owed.** JOB-61 (`docs/manual-checks.md`): the owner's playback check. Nothing to file.

### CP1 — the owner's checkpoint: T1 cut by deleting words

- **What a person gets:** the first real use of the Transcript tab. In the build with TX3 landed,
  the owner cuts T1 (S-TH1) again, this time reading it in the Transcript tab and cutting by
  deleting words, to a state they would publish.
- **Recorded** in "The owner's trials" in CJ-5's form: each exit to another tool or give-up with its
  reason, each slow step, each word cut that sounded wrong (with its time), and what the owner wants
  from TX4–TX7 that the plan does not give. Findings become amendments of TX's phases or of CJ-2, or
  issues, before TX4 starts.
- **Lane A:** TX4 does not start until the record is in; CJ5a, which needs nothing from TX, is built
  meanwhile. Lanes B and C go on.
- **No code, no proof, no mutants.** The checkpoint is not a JOB row (CJ-5).
- **Depends on:** TX3.

### CJ5a — `keep_range`: a timeline range as a whole project

The first draft's FC1 and FC2 are CJ5a and CJ5b, made shared because VR3 builds its copy on the same
derived document; FC1 and FC2's numbers are retired. CJ5a and CJ5b share CJ-50…CJ-59.

- **What a person gets:** nothing visible; the core can turn a project into exactly one range of its
  timeline.
- **Decisions (draft):**
  - **CJ-50 — `keep_range {from, to}` answers the project holding only `[from, to)` of its top-level
    timeline, moved to start at 0.** `from` and `to` are snapped as `split` snaps its `at`. Every
    clip on every track, locked or not (the source document keeps its locks; the op is applied only
    to a derived document's handle), that a bound lies strictly inside is split there by `split`'s
    own rules (`split_under_playhead`; SR-18 (e) for a ramp; W-3's word rebase for a timed caption
    page; AU-92 for a linked pair); clips wholly outside are removed; the rest move by −`from`.
    Markers inside the range are kept and moved; the others are removed. Media no kept clip plays,
    in any container, are removed by `remove_media`'s rule, so a derived project lists and carries
    only what it plays (anything else a range leaves unused is settled at CJ5a's design pass and
    written here before code).
    - **THE overlap rule at the edges (N1).** At `from`, on each track where an overlap `[os, oe)`
      has `os ≤ from < oe`, the outgoing clip's piece `[from, oe)` is dropped and the incoming clip
      starts at `from` with its `transition_in` cleared (a hard start). At `to`, where `os < to ≤
      oe`, the incoming clip's piece `[os, to)` is dropped and the outgoing clip ends at `to`. The
      edges stay where asked. A dropped piece's linked partner goes too only when it breaks the rule
      itself; otherwise `finish`'s `settle_links` clears its link. Every track of every answer
      passes `check_overlap_rule` (`transition.rs:281–339`), which `validate` does not run.
    - **A nest clip a bound lies strictly inside is refused**, naming it: "Clip N is a nest across
      the range's edge; a nest clip has no in point, so a cut there would replay it from its start.
      Move the edge, or open the nest and unnest it." (Confirmed against `nest.rs`'s rules at the
      design pass.)
    - **Arguments (N2).** `to` not after `from` is invalid input (`Err`), not a refusal;
      `ordered_range` is not followed (an empty keep is not an identity). A range where no clip
      plays is a refusal: "Nothing plays between <from> and <to>."
    - **Document-level, with no tool.** It joins `scope.rs`'s `refused_inside` (its eleventh arm)
      and `ReelOp.documentLevelNames` (the tenth name, `add_adjustment_clip` still the one arm the
      list lacks; `app/CLAUDE.md`'s "eight" corrected, and `scope.rs:172`'s "fifty-three" rewritten
      as `OP_COUNT` less the arms at landing — 65 − 11 = fifty-four if no other op has landed — in
      the same change); it is `opsWithoutTools`' first entry, one line of
      wiring in the frozen `AgentServer.swift` with its reason: "it discards everything outside a
      range; only File ▸ New Project from Range… and `new_project_from_range` apply it, to a derived
      document". Spec §6a's "Ten ops" becomes eleven.
- **Core:** `edit_keep_range.rs` (new): the op, N1, N2, the nest refusal, markers, media pruning;
  the `op_rows.rs` row, `edit.rs`'s enum, dispatch and module-doc row, `scope.rs`.
  `core/tests/keep_range.rs`: fixtures with `from` and `to` at `os`, inside and at `oe` of an
  overlap, every track checked by a half-shorter oracle of the tests' own, not the core's. The one
  there today is inside a private `fn valid_shift` (`core/tests/common/transition_oracle.rs:296`,
  the check at :312) in a file test binaries include by `#[path]` and which carries `#[test]`
  functions, so including it would re-run them; CJ5a lifts the check into a `pub fn
  overlap_rule_holds(project: &Value) -> bool` in a new `core/tests/common/overlap_oracle.rs`, which
  `valid_shift` then calls (its tests unchanged, run once before and after the lift), and
  `keep_range.rs` includes the new file alone; a ramp, a timed caption page, a
  linked pair and a locked track across an edge; markers; media pruning; the nest refusal; N2. No
  format change.
- **FFI:** none (`rc_project_apply`).
- **Swift:** `ReelOps.swift`'s builder and `documentLevelNames`; the `opsWithoutTools` line.
- **MCP mirror:** none (no tool; CJ5b's `new_project_from_range` is its door).
- **Docs:** spec §6 (the op; §6a's count), §7.10; `core/CLAUDE.md`; `app/CLAUDE.md` (the names);
  root `CLAUDE.md`'s parity text if it names the empty `opsWithoutTools`.
- **Acceptance:** `cargo test --release --test keep_range`; `make gate`.
- **Mutants** (5): the outgoing sliver kept at `from` (the oracle); the incoming sliver kept at
  `to`; a reversed pair ordered instead of `Err`; markers outside kept; the nest refusal removed.
- **Manual checks:** none. **Depends on:** CJ0b (T1, T4). **Lane** A (during CP1).
- **Questions:** none expected.

#### CJ5a's record (2026-11-01)

**Landed.** `keep_range {from, to}` (spec §11 CJ-50 (a)–(h), recorded and committed before the
code) on lane A's branch, base `822973cd`. No FFI, header, tool or format change;
`RC_FORMAT_VERSION` is unchanged. Every count below is a `wc -l` or a run's own output.

- **Core:** `core/src/edit_keep_range.rs` (new, 248 lines): bounds snapped and clamped, `to ≤ from`
  an `Err`; the nest refusal before any cut; both bounds cut on every track through `split_clip` and
  `pair_split_halves`, with a piece → source-id map; THE overlap rule at the edges judged on the
  source's `overlaps_on_track`, with K14's same-overlap exception; keep and move; markers;
  `prune_unused` (nests reached transitively from kept clips; media by source, `look_media_ids` and
  a kept media's `color.lut`, to a fixpoint); "Nothing plays" and the short-transition sentence
  (source ids); exit through `finish`. `op_rows.rs`'s row after `lift_range`'s, `OP_COUNT` 64 → 65,
  `Op::KeepRange` and its dispatch, `edit.rs`'s table row and scope paragraph ("Eleven ops",
  "fifty-four"), `scope.rs`'s eleventh arm and "fifty-four", `edit_split.rs`'s splitter list.
- **Tests:** `core/tests/common/overlap_oracle.rs` (new, 36 lines), `overlap_rule_holds` lifted out
  of `transition_oracle.rs`'s `valid_shift`, which now builds the shifted copy (the locked track 4
  left out, as its check skipped it) and calls it; `transition_bounded` 12 passed, 0 failed before
  the lift and after. `core/tests/keep_range.rs` (new, 440 lines; tests are outside the ledger's
  cap): K1–K14 as fifteen tests (K7's two cases apart), each applied answer held to the oracle. The
  enumerations: `scope.rs` (refused, every_op, `OP_NAMES.len()` 65, the "eleven" names, the
  no-scope row with a marker at 5 s first), `edit_tests.rs`'s `op_table()`, `op_ticks_timeline.rs`'s
  `keep_range.from`/`.to` vectors and `op_ticks.rs`'s 46 / 33 / 51.
- **Swift:** `ReelOps.swift` `keepRange(from:to:)` and `documentLevelNames`' tenth name (doc nine →
  ten, `add_adjustment_clip` the eleventh); `AgentServer.swift`'s `opsWithoutTools` its first entry
  with its reason, "None today" → "One today", nothing else.
- **Proofs:** `OPS_WITHOUT_TOOLS = {"keep_range"}` in `op_catalog_proof.py` (65 ops, the op-tool
  group over `ops − OPS_WITHOUT_TOOLS`, and no tool named for it), `op_argument_proof.py` (`OPS` 65,
  section 1 and 2 the same, section 5's count over `OPS − 1` op tools) and `recording_probe.py`'s
  section 7 (7a's set and 7c's list).
- **Documents:** spec §6b's bullet (482 → 492) and splitter list, §6a's "Eleven ops" (107 → 109),
  §7.10's `edit_keep_range.rs` row and `edit_split.rs`'s list (132 → 133), the spec README's cells
  and the `11-decisions/` total (16911 → 16962), the decisions index's CJ-50 row and the file row
  (216 → 266).
- **Checks in the loop:** `cargo test --release --test keep_range` 15 passed; `--test scope --test
  edit_tests --test op_ticks --test op_table --test op_names --test op_schemas --test keep_range
  --test transition_bounded` all ok (38, 53, 6, 8, 5, 10, 15, 12 passed); `cargo clippy
  --all-targets -- -D warnings` exit 0, no warning; `make typecheck` exit 0, no error, the four
  baseline warnings; `spec_index_proof.py` 222/222; `recording_probe.py --only catalog` 31/31;
  `make app-debug` BUILD SUCCEEDED (the Debug parity trap did not fire).
- **Mutants** (nine, the spec's M1–M9, once against `--test keep_range` on the final code): all
  killed — M1 (K2, K14), M2 (K3), M3 (K11), M4 (K8), M5 (K10), M6 (K4), M7 (K9), M8 (K12), M9
  (K14).
- **`make gate`** once, at `9e4b8f5f` with this record written: PASS 463 s — names 1 s, typecheck
  10 s (the four baseline warnings), fmt 4 s, lint 10 s, test 273 s (199 result lines, 1991 passed,
  0 failed), app 164 s (D25 and D26 ok).
- **Against Release** (one instance from `proof_app.py launch --app release`, stopped by its pid):
  `op_catalog_proof.py` 23/23; `op_argument_proof.py` 179/180 on its first run — section 4's count of
  opaque-object arguments still said 14, where the core has published 16 since format 36's
  `set_track` `compressor` and `limiter` (AU-150), whose two doors the same run passed — then
  180/180 with the count at 16 (the only edit between the runs); `grep "Frame Job: "` on its log
  printed nothing; `recording_probe.py --only catalog` 31/31 after the gate.

**Deviations.** The road map's five mutants are the spec's nine. The draft's "removed by
`remove_media`'s rule" for media is CJ-50 (f)'s rule (source, looks, a kept media's `color.lut`),
and nests a range leaves unused go too, as the draft left to the design pass. `scope.rs`'s
count is "fifty-four" (`OP_COUNT` 65 less eleven arms), per CJ-8 (g)'s reading that the old
"fifty-three" was stale. `op_catalog_proof.py` and `op_argument_proof.py` also check that no tool
is named for an `OPS_WITHOUT_TOOLS` op, inside the spec's section-1 check. `op_argument_proof.py`'s
opaque-object count 14 → 16 is outside the spec's list: a stale pin in a file this phase edits, found
by its Release run.

**Found, not fixed (out of scope; owed as an issue, its draft in the implementer's notes).**
`split`, `lift_range` and `ripple_delete_range` each leave a piece shorter than twice a
neighbouring transition and answer Applied: on A [0, 4 s), B [3 s, 8 s) with a 1 s dissolve, each
at 2.2 s applied with the half-shorter oracle false (a scratch test, removed after the run).
`keep_range` refuses that case (CJ-50 (g)).

**Review.** Verdict pass, one nit: `core/tests/keep_range.rs` is 440 lines, over the 400-line
cap for a new file if the cap is read past the size ledger (`app/Sources`, `core/src`,
`graphic/src`), which it is not; left as it is. The reviewer walked rule (d) through `from` and
`to` at, inside and at the end of an overlap, a three-clip chain and both bounds in one overlap,
and found the code dropping the piece CJ-50 says each time.

**Integration.** Cherry-picked onto `worktree-creator-jobs` after CU0a. Three conflicts, all
indexes, each kept both sides: `11-decisions/creator-jobs.md` holds CU-1…CU-9 and then "The
phases' decisions" with CJ-50; its index row follows CU-9's; the file row's summary names
CU-1…CU-9 and then CJ-50, its Lines cell 275 → 325, and the spec README's `11-decisions/` total
17006 → 17057; §7.10's cell 133 → 134 (CU0a had already taken it to 133). Map entries at
integration: `core/CLAUDE.md`'s `edit_keep_range.rs` entry after `edit_time.rs`'s, and
`app/CLAUDE.md`'s `documentLevelNames` sentence "(eight names)" → "(ten names: its eleven arms
but `add_adjustment_clip`, sent scoped)". `make gate` after the picks and these edits: names,
typecheck, fmt, lint, test (199 result lines, 1991 passed, 0 failed) and app (D25, D26 ok) each
pass, "gate: PASS 346s". Then, on the integrated tree: `recording_probe.py --only catalog` 31/31;
against its Release app `op_catalog_proof.py` 23/23 and `op_argument_proof.py` 180/180, and
`grep "Frame Job: "` on the log printed nothing.

**Owed.** No manual check. The splitters' short-piece finding above, filed as an issue at
integration (`ai-drafted`, `low-priority`).

### CU3a — the cursor in the model, then drawn as part of the layer

CU3a is two pipelines (CJ-7's re-split): CU3a1 puts the cursor in the model and the recipe,
readable by agents and byte-identical for every project without one; CU3a2 draws it and makes
files wait for it. "CU3a" in a dependency means both. They share CU-30…CU-39.

- **Decisions (draft):**
  - **CU-30 — `media.cursor` and `video.cursor` (format p, CU3a1).** `MediaCursor {path,
    bookmark?, in_picture}` (`media.cursor`, written only when set) in `model_media.rs`;
    `CursorProps` (`video.cursor`, written only when set): `show` (true), `scale` (1, 0.25–8),
    `style` (`recorded` | `arrow`), `smoothing` (0, 0–1), `hide_idle` (null, or 0.5–30 s), `clicks`
    (`none` | `ripple`), `click_color` (`#ffffffcc`, G-25's grammar), `click_size` (1, 0.25–4).
    `scale` and `click_size` animate; `show`, `style`, `clicks` and `click_color` switch at an
    action's end; `smoothing` and `hide_idle` are the clip's — the recipe reads them from the BASE
    props, as `audio_track.rs` reads a base `audio.mono`, so no frame asks for a new smoothing (an
    end patch may carry them, CI-3 leaves the door, and they have no effect).
  - **CU-32 — The recipe's `cursor` key** (a layer's next key in landing order): `null` unless the
    clip's media has `media.cursor`, `in_picture` is false and `show` (or ripples) is on; otherwise
    `{media, at, reversed, smoothing, hide_idle, props}`, `at` the source tick in the stream the
    clip PLAYS (through S for a ramp, the held time for a still), `reversed` true when it plays
    reversed; Swift mirrors through `ReverseMirror` (D4-6).
  - **CU-33 — The composite inside `layerSample` before the grade (CU-4), at `texture(5)`** (CU3a2),
    the sprite lifted in an HLG project like any layer Frame Job draws (`LayerLift`), the ripple
    colour through `liftSDR`.
  - **CU-35 — An older project, and a media without a file, renders byte-identically.**
  - **CU-37 — A track not ready yet (CU3a2):** the preview draws without it and redraws on
    `.cursorTrackDidLand`; an export or `render_frame` waits; an unreadable or refused file is a
    `cursor_warnings` entry (each media once, the core's sentence) and the clip draws without a
    cursor.

#### CU3a1 — the cursor in the model and the recipe

- **What a person gets:** nothing drawn yet. An agent (or a proof) adds a media with a `cursor` in
  its `add_media` record, sets `video.cursor` with `set_video`, and reads both back through
  `get_project`; the recipe carries the `cursor` key CU3a2 draws. Every existing project is
  byte-identical.
- **Core:** `model_cursor.rs`; `cursor_props.rs` (`check_cursor`, `clamp_cursor`, one line each from
  `props_check.rs` and `actions_clamp.rs` after U5); `recipe_cursor.rs` (the key);
  `recipe_layer.rs`; `add_media`'s record carries `cursor`, and `relink_media`'s probe carries it as
  `original` is carried (the probe's value replaces the stored one); the format bump (`format.rs`,
  `format_history.rs`, `core/tests/schema_vN.rs`, the header's `#define`) — provisional, "(format
  p)" until it lands. `core/tests/cursor_recipe.rs` (the key's `at` through ×2, a ramp, a still and
  a reversed clip against an oracle; `smoothing` and `hide_idle` from the base at every time; `null`
  for `in_picture` and for `show: false` with no ripples; the refusals and clamps).
- **FFI:** the bump's `#define`; the key travels in the recipe JSON.
- **Swift:** `MediaDescriptor`, `MediaSnapshot` gain `cursor`; `VideoProps.swift` gains `cursor`
  (`CursorProps.swift`, a read-only mirror); `VideoPatch`; `RecipeLayer.cursor` decoded (not yet
  drawn).
- **MCP:** `set_video`'s description names the `cursor` keys (and that `smoothing`/`hide_idle` have
  no effect in an end); `get_project` shows `media.cursor` and `video.cursor`.
- **Docs:** spec §5.2a, §7.3; `core/CLAUDE.md` (`model_cursor.rs`, `cursor_props.rs`,
  `recipe_cursor.rs`, the layer's key count); `app/CLAUDE.md` (`CursorProps.swift`).
- **Acceptance:** core tests; the proof rows against Release; `make gate`.
- **Proof rows** (`cursor_layer_proof.py`'s first rows, Release; no grant): L1 `add_media` with a
  `cursor` and `set_video {cursor}` read back through `get_project`, a malformed `click_color` and a
  `scale` of 9 refused in their sentences; L3 a pre-CU recording's project before and after the
  bump: `get_project` and frames byte-identical; L9 an end naming `smoothing: 1` on a base of 0: the
  recipe's `smoothing` is 0 at every time (read through a probe of `ReelProject.recipeJSON`).
- **Mutants** (4): `at` without S (core test); `in_picture` ignored (L3); `show: false` still keying
  ripples (core test); `smoothing` from the evaluated props (L9).
- **Manual checks:** none. **Depends on:** CU2, CU0a (U5), CJ0b (T2), CJ0d (T11, T14). **Lane** B.

#### CU3a1's record (2026-11-01)

**Landed.** Lane B, base `0210dfe7` (I's HEAD, CJ2b; the harness made the worktree at `eb350b86`
and it was fast-forwarded to `0210dfe7` before any edit, nothing of its own on it). Three
commits: the decisions (`24652dc7`: CU-30, CU-32, CU-35 and CU-39 with their index rows), the toll
(`e5594294`), then the code, the proof and the documents (`6b2e2179`); landed on
`worktree-creator-jobs` as one commit, format 38 kept (no other phase had taken it). Format 38
was provisional: CO2a1 (lane C) bumps the format and
adds a layer key after `dissolve` too, and whichever lands second renumbers its version and its
key count. Nothing is drawn: an agent adds a media with a `cursor` through `add_media`, sets
`video.cursor` through `set_video` and reads both through `get_project`; every layer carries
`"cursor": null` unless a media cursor would draw.

- **Two deviations.** The media record's decision is **CU-39**, not the spec's CU-31: the road
  map already drafts CU-31 for CU3c (the stream's cursor only In the picture), so CU-31 keeps that
  meaning; the decisions file's lead-in says so. The toll moved lines 24–191, not 23–191: line 23
  is `shapeNames`, the shape rows'.
- **The toll paid here, CO2a1's by schedule:** `AgentCatalog+Properties.swift`'s video patch
  (`filterNames` through `videoPatchDescription`) to `AgentCatalog+VideoPatch.swift`, a pure move
  gated alone (`make typecheck`, its 4 baseline warnings; the moved block diffed line-identical
  but for `videoPatchDescription`'s dropped `private`); 410 → 244 lines. CO2a1 does not repeat it.
- **CU-30's split and freeze:** `with_base_cursor` (`cursor_props.rs`) is the one statement that
  `smoothing` and `hide_idle` are the base's; the recipe, `split`'s second half and
  `freeze_frame`'s still read it. On a clip with no `video.cursor` an end's cursor keys switch at
  the end, as `shadow` and `look` do; `set_video {cursor: {}}` gives it one to animate from.

| File | Lines | What |
|---|---|---|
| `core/src/model_cursor.rs` | 93 | `MediaCursor`, `CursorProps`, `CursorStyle`, `CursorClicks`, the ranges and `CURSOR_CLICK_COLOR` |
| `core/src/cursor_props.rs` | 114 | `check_cursor`, `clamp_cursor`, `check_media_cursor`, `with_base_cursor` |
| `core/src/recipe_cursor.rs` | 67 | `Project::layer_cursor`, the layer's 27th key |
| `core/src/edit_time.rs` | 599 | `freeze_frame`'s still through `with_base_cursor` (wiring, 595 before) |
| `core/tests/cursor_recipe.rs` · `schema_v38.rs` | 465 · 148 | 13 and 5 tests |
| `app/Sources/CursorProps.swift` | 132 | the mirrors: `CursorStyle`, `CursorClicks` (`off` for the core's `none`), `CursorProps`, `MediaCursor`, `RecipeCursor` |
| `app/Sources/AgentCatalog+VideoPatch.swift` | 203 | the toll's 180 lines and `cursorClause` |
| `app/Sources/AgentServer+Media.swift` | 552 | `mediaCursor`, `add_media`'s `cursor` |
| `tools/proof/cursor_layer_proof.py` · `cursor_layer_probe.swift` | 365 · 241 | B0, L1d, L3r, L9 (probe), L1, L3, Z1 (app) |

**Measured.**

- `cargo test --release --test cursor_recipe`: 13 passed (`at` at ×2, through a linear ramp's
  S(t) = t + t²/D, a still, a reversed clip at ×1.5 and a nested clip; `smoothing` and
  `hide_idle` from the base before, inside and after an action naming them; a split at 3.5 s and
  at 2 s and a freeze at 3.5 s keeping the base; an end on a clip with no cursor switching at the
  end; the null cases; every refusal's sentence; the clamps through an end; a relink's probe
  replacing, clearing and, with none, keeping the cursor; `{}` storing the eight defaults).
  `--test schema_v38` 5 passed; `--test recipe` 15 passed (`LAYER_KEYS` 27); `--test
  model_tests` 31, `edit_tests` 53, `ramp_split` 10, `ramp_freeze` 1 passed.
- `cargo fmt`, `make lint` clean; `make typecheck` 0 errors and the 4 baseline warnings;
  `swift_build.py typecheck tools/proof/cursor_layer_probe.swift` exit 0.
- Mutants, each run once and reverted byte-identical (SHA-256 checked), all caught: M1 `at`
  through `timeline_to_source` (`cursor_recipe`'s ramp test); M2 the `in_picture` test dropped
  (L3r after `make rust`: the recipe text changed at all five times); M3 the `show` test dropped
  (`cursor_recipe`'s null test); M4 `layer_cursor` without `with_base_cursor` (L9 after `make
  rust`: `smoothing` 0.25, 0.75, 1 inside and after the action); M5 `edit_split.rs`'s
  `with_base_cursor` dropped (`cursor_recipe`'s split test).
- `cursor_layer_proof.py` on Debug: 7/7. `make gate`: PASS 419 s (names 1, typecheck 7, fmt 3,
  lint 7, test 238, app 163). `RC_PROOF_APP=release cursor_layer_proof.py`: 7/7 — L3 reads the
  version-37 fixture through this build at 38 (every key equal, no `cursor`), three frames, and
  after a save to a new package and a reopen `get_project` equal and the three PNGs
  byte-identical; no older build is driven.

**Review.** One review, verdict pass with no finding: it checked `layer_cursor`'s null cases and
`at`, the re-clamp after `with_base_cursor`, a probed relink replacing or clearing the cursor,
`MEDIA_KEYS` at 13, and a `VideoPatch` with a nil `hideIdle` writing `NSNull` (which clears the
stored `hide_idle`, the key walk letting `null` through). No fix pass. The CLAUDE.md map entries
(`core/CLAUDE.md`'s three modules and "twenty-seven keys"; `app/CLAUDE.md`'s `CursorProps.swift`,
`RecipeLayer.cursor` and `AgentCatalog+VideoPatch.swift`) were applied when the phase landed.

**Owed.** No manual check and nothing to file. Drawing is CU3a2's; CO2a1 renumbers its format
past 38 and its layer key past the twenty-seventh, and does not repeat the `+Properties` toll.

#### CU3a2 — the cursor drawn, and files that wait for it

- **What a person gets:** a media whose cursor file says the picture has no cursor gets its cursor
  drawn by Frame Job, following every zoom and transform. Until CU3b only a media added with a
  `cursor` in its `add_media` record has one (an agent, a proof).
- **Swift:** `RecipeSource` publishes media cursor URLs beside the LUT URLs; new
  `Compositor+Cursor.swift` (mirrors `at` through `ReverseMirror` when `reversed`, pivot the media's
  model duration; asks `CursorTracks.ready` at the base smoothing, then `state`; binds the sprite
  and uniforms, or nothing until the track lands); `ReverseMirror.swift`'s doc gains its fourth
  reader; `Compositor.metal` (`layerSample` composites sprite and analytic ripples over the texel
  before `gradeSample`, behind one uniform-driven branch; every draw running `layerSample` binds
  `texture(5)`, a 1×1 placeholder when no cursor is drawn); `LayerUniforms` (groups of four in
  landing order: sprite rect, up to four ripples, ripple colour and size; Swift and Metal in one
  edit; the size proofs re-pinned as CO2a2 lists them); new `CursorSprites.swift` (image textures
  from `image` requests, once per image, lifted in HLG); new `Exporter+Cursor.swift` (an export or
  `render_frame` waits for every cursor track its range needs, `Exporter+RampAudio`'s shape, and
  publishes `cursorWarnings`). `MetalRenderer.swift`: no new pipeline.
- **MCP:** `render_frame` draws the cursor; `render_frame`, `export`'s answer and `export_status`
  gain `cursor_warnings` in `graphic_warnings`' shape (G-24 (c)).
- **Docs:** spec §7.5b; `app/CLAUDE.md` (the new files, `ReverseMirror`'s fourth reader, the uniform
  block's size); spec §7.9 (`cursor_warnings`).
- **Acceptance:** a project made over MCP with `add_media` (a `testsrc2` movie with no cursor and
  its fixture file) and `add_clip` draws its cursor at the file's positions; zoom actions carry it;
  the proof against Release; `make gate`.
- **Proof rows** (`cursor_layer_proof.py`'s drawing rows, and a probe through `MetalRenderer`;
  Release; no grant): L2 a 2× zoom: the cursor's canvas position equals (★) of its source position ≤
  1 px; L4 a ramped clip draws the cursor at S(clip time), a reversed one at `ReverseMirror`'s
  forward time, ≤ 1 px; L5 in HLG the cursor's pixel equals `liftSDR` of the sprite's; L6 export
  against `render_frame` at three times: identical; L7 cost against `show: false` with no ripples,
  median of 120 frames: ≤ 0.3 ms at 1920×1080 and ≤ 1 ms at 3840×2160 and 5120×2880 on the owner's
  Mac, no texture allocated per frame; L8 parity with a burned pointer (the sprite burned at the
  file's positions against the clean movie with the file, each with a blur filter, an obscure region
  over the pointer and a +1 exposure grade) ≤ 2/255 per channel; L10 an unreadable cursor file:
  `cursor_warnings` names it and the frame has no cursor; L11 with `-RCDevCursorLoadHold 2`, an
  export started at once draws the cursor in every frame.
- **Mutants** (4): the reverse not mirrored (L4); the composite after `gradeSample` (L8); the HLG
  lift skipped (L5); the export not waiting (L11).
- **Manual checks:** none here (they need Separate recordings, CU3c).
- **Depends on:** CU3a1, CJ0d (T14). **Lane** B.

#### CU3a2's record (2026-11-01)

**Landed.** Lane B, base `0ff76ec2` (I's HEAD, CU3a1; the harness made the worktree at
`eb350b86` and it was fast-forwarded to `0ff76ec2` before any edit, nothing of its own on it).
Three commits: the decisions (`e06c1592`: CU-33, CU-37 with their index rows), the toll
(`c33db189`), then the code, the proof and the documents (`8ca1b326`); landed on
`worktree-creator-jobs` as one commit after TX1 and CO0. No core, FFI or format change. The
uniform block's size (156 floats, 624 bytes) stands: CO2a2's group had not landed, so CO2a2
appends after the cursor group and re-pins the sizes (CJ-8 (b)).

- **The toll paid here, CO2b's by schedule:** `Exporter.swift`'s `// MARK: - Offline single
  frame` (478–597, `renderFrame`, `renderFrameReported`, `scaledSize`) to `Exporter+Frame.swift`,
  a pure move gated alone (`make typecheck`: 0 errors, the 4 baseline warnings, the
  `copyCGImage` one now in `Exporter+Frame.swift`; the moved block and the rest of the file
  diffed line-identical against the base), `gate.py`'s `TYPECHECK_BASELINE` row moved with it;
  598 → 477 lines. CO2b does not repeat it. `designs/adr/app-file-history.md`'s "`renderFrame`
  stays in `Exporter.swift`" now says where it is.
- **One refinement of CU-33 (b), found by L8 and written into the decision.** Composited per
  SAMPLE as first built, the clean movie with its file against the burned movie differed by up to
  10/255 at the sprite's edge once a blur was on (every pixel over 2/255 within the blur's reach
  of the sprite): a tap between texels read bilinear(background) with bilinear(sprite) over it,
  where a burned pointer gives bilinear(background with the sprite in it). The composite is now
  made PER SOURCE TEXEL for a sample within 2 px of the sprite or a ripple (`cursorFootprint`:
  the bilinear footprint's four texels, each read at its centre with the cursor laid over it,
  weighted as the sampler weights them); every other sample is the one hardware sample it was.
  L8 then measured 1/255. The footprint's loop is kept from unrolling (`#pragma nounroll`): with
  four inlined composites every fragment paid for them (L7 at 5120×2880 measured 1.196 ms, then
  0.963 ms with the near test unrolled by hand, then 0.346 ms twice with the pragma).
- **Deviations.** `ExportQueueController.swift` takes three lines, not two (the property, the read
  before the exporter is dropped, the copy). `RecipeSource.setMediaURLs` re-resolves a key's
  cursor files when a cursor media's record, duration or rate changed, not its record alone,
  because `CursorFile` carries the pivot and the frame. `tools/proof/lut_probe.swift`'s call of
  `setMediaURLs` passes a project (the signature gained it), and `precision_proof.py`'s
  `no-source-clamp` mutant is re-aimed at the clamp's new line in `layerSample`. The probe's L7
  compose timing is behind `FRAMEJOB_DEV_TOOLS` (the proof builds with it), so `swift_build.py
  typecheck` of the probe passes without the define. L8's grade is exposure +1 AND saturation
  −0.5: exposure is step 4c, after `layerSample`, so it alone cannot tell a composite before
  `gradeSample` from one after it; saturation is in `gradeSample`. Outside the Files list, each
  a sentence or an anchor this phase made stale: `CursorTracks.swift`'s header (its owners'
  wiring), `designs/adr/app-file-history.md` (where `renderFrame` lives), `hdr_proof.py`'s
  `relabel-in-renderframe` mutant (re-aimed at `Exporter+Frame.swift`), and `phase8_chrome.py`'s
  View-menu list (below).

| File | Lines | What |
|---|---|---|
| `app/Sources/Exporter+Frame.swift` | 134 | the toll's 120 lines; `renderFrameReported` waits for its frame's cursor tracks and returns their warnings |
| `app/Sources/Exporter+Cursor.swift` | 69 | `ExportCursorWarning`, `waitForCursors`, `cursorSentences` |
| `app/Sources/CursorFiles.swift` | 48 | `CursorFile`, `CursorFiles.files(of:)`, `requests(of:files:)` |
| `app/Sources/Compositor+Cursor.swift` | 99 | `MetalRenderer.cursorSprite`, `cursorTime`, `rippleColour` |
| `app/Sources/CursorSprites.swift` | 82 | the sprite textures, an LRU of 64, `uploads` |
| `app/Sources/EditorViewController+Cursor.swift` | 16 | `cursorTrackDidLand` |
| `app/Sources/RecipeSource.swift` | 247 | cursor files per key, `setMediaURLs(_:project:for:)`, the asynchronous release |
| `app/Sources/Exporter.swift` | 488 | `cursorWarnings`, the wait before `withRampAudio` |
| `app/Sources/EditorViewController.swift` | 1,082 | one observer (wiring, 1,080 before) |
| `app/Sources/Playback.swift` | 592 | line 241 only, net 0 |
| `app/Resources/Shaders/Compositor.metal` | — | the 24 fields, `compositeCursor`, `nearCursor`, `cursorFootprint`, `displayUV`, `texture(5)` on both layer fragments |
| `tools/proof/cursor_layer_proof.py` · `cursor_layer_probe.swift` | 919 · 504 | L7 (probe), L2, L4, L5, L6, L8, L8r, L10, L11 (app) |

**Measured.**

- `make typecheck`: 0 errors and the 4 baseline warnings, the `copyCGImage` one at
  `Exporter+Frame.swift` (after the toll, and again after the code). `swift_build.py typecheck
  tools/proof/cursor_layer_probe.swift`: exit 0. The shader compiled by `xcrun metal` with only
  its two old unused-constant warnings.
- The size pins at 624 bytes: `tone_proof.py --only P3`, `wheels_proof.py --only P3`,
  `look_proof.py --only L3`, `curves_proof.py --only P13`, `hdr_proof.py --only P9`, each exit 0.
- `cursor_layer_proof.py` on Debug, whole: 16/16 after the per-texel composite, and L8 3/3
  again once its obscure region was put over frame 50's pointer (it had missed the pointer). The
  first drawing-rows run, per sample, was 7/11: L8 106/255 from the burned movie's own one-frame
  offset (ffmpeg `overlay`'s `n` measured to start at 1; frames now counted from `t`), then
  10/255 from the composite, above; L4 a misspelt ramp shape; L7 no `default.metallib` beside
  the probe.
- Mutants, six, each run once on Debug and restored byte-identical (SHA-256), all caught: the
  reverse not mirrored (L4: the reversed tips at (105, 65), (195, 95), (330, 140) against (372,
  154), (282, 124), (147, 79)); the reversed time without its one-frame offset (L8r: the drawn tip
  3 px right and 1 px down of the burned pointer at all three frames); the composite after
  `gradeSample` (L8: 36/255 at frames 20 and 90); the HLG lift skipped (L5: 20.233/255); the
  export not waiting (L11: 42 of 120 frames with the sprite, frame 0 without); a failed track
  failing the export (L10: no sentence, and `export: Cancelled.`).
- `make gate`: PASS 437 s (names 1, typecheck 6, fmt 3, lint 15, test 230, app 181).
- `RC_PROOF_APP=release cursor_layer_proof.py`: 15/16 at load average 61 (three lanes building;
  L7 alone over: 0.371 ms at 1920×1080, 1.047 ms at 5120×2880), then `--only B0,L7` 0.125 /
  0.231 / 0.377 ms, then the whole proof again against Release: **16/16** — L7 0.130 ms at
  1920×1080, 0.186 ms at 3840×2160, 0.359 ms at 5120×2880 (medians of 120 frames, 3 runs each,
  the probe built `-Onone`), `uploads` 1 after the first frame and the last; L2 the tip within
  0.03 px of (★) at three frames of a 2× zoom; L4 exact at three ramp frames and three reversed
  ones; L5 0.057/255 from `liftSDR`; L6 1/255 at three frames, two with a ripple; L8 1/255, 0/255,
  1/255; L8r within 0.43, 0.31 and 0.77 px; L10 the sentence, the byte-identical frame and one
  `cursor_warnings` entry; L11 120 of 120 frames; Z1 nothing in either launch's log. L7 across the
  session, at 1920×1080 / 3840×2160 / 5120×2880 (ms): 0.071 / 0.169 / 0.127 (per sample);
  −0.051 / 0.089 / 1.196 (per texel, unrolled); 0.053 / 0.245 / 0.963; 0.041 / 0.317 / 0.346;
  0.011 / 0.033 / 0.346 (the pragma, Debug's whole run); 0.371 / 0.435 / 1.047 (load 61); 0.125 /
  0.231 / 0.377; 0.130 / 0.186 / 0.359 — eight runs; the owner's Mac is the figure the road map
  names.
- `phase8_chrome.py`: 149/150, the `LayerUniforms` 624-byte pin passing and View's last group
  failing on its own stale list (road map "audio" AP7 put Loudness Meter after Scopes; a check
  this phase did not change); the list fixed, 150/150.

**Review.** One review, verdict pass, three nits, none fixed in the lane; all three resolved at
integration. It accepted the per-texel composite as a reading of CU-33 (inside `layerSample`,
before `gradeSample`, behind `cursorEnabled`; a layer with no cursor keeps the one hardware
sample, so CU-33 (h) holds, as L3 and L10 show byte for byte), and checked the deadlock fix (the
release on a utility queue, `RecipeSource`'s lock dropped before `CursorTracks.want`, the two
locks never nested) and that `waitForCursors`' failure loop always removes the failed path.
- `nearCursor`'s 2 px margin covers `cursorFootprint`'s ±1 texel only while a texel is at most
  2 display px: its doc in `Compositor.metal` now states that assumption (true while the bound
  texture is the source's display size, as every source is today).
- `exportResult`'s `cursorWarnings` lost its `= []` default, so a future caller cannot drop the
  warnings silently (the one caller already passes them).
- `renderFrameReported`'s `try? waitForCursors(…)`: its comment now says `.cancelled`, the only
  throw, cannot happen with `cancelled: { false }`.

**Integration.** Cherry-picked (`e06c1592…8ca1b326`) onto `worktree-creator-jobs` after TX1 and
CO0. Conflicts only in the indexes, the decision file and the proof README, each kept both sides:
`creator-jobs-2.md` holds TX1's block and then CU3a2's (475 lines, its index row 475, its summary
TX1's clause then CU-33, CU-37's before "the series continues"); the spec README's §7.9e cell
503 and `11-decisions/` 17888 in 37 files (`spec_index_proof.py` 231/231); `tools/proof/README.md`
puts CU3a2's subsection under CU3a1's and TX1's section after it. `setMediaURLs`' callers, every
`RenderedFrame` and `exportResult` site and the `LayerUniforms` size pins were re-read on the
merged tree: TX1 and CO0 added none. The CLAUDE.md edits the lane listed were applied: root
`CLAUDE.md`'s baseline note (1 in `Exporter+Frame.swift`); `app/CLAUDE.md`'s `ReverseMirror`
(four readers), the uniform block (156 floats, 624 bytes, the HLG and cursor groups) and
`texture(5)`, the compositor list (`Compositor+Cursor.swift`, `CursorSprites.swift`), the cursor
entry (`CursorFiles.swift`, `EditorViewController+Cursor.swift`, the wiring), `RecipeSource`'s
cursor files, `cursorURL(for:)`, the Exporter list (`Exporter+Frame.swift`,
`Exporter+Cursor.swift`) and `RecipeLayer.cursor` drawn. `make gate` after the picks, the nits and
these edits: names 1 s, typecheck 13 s (the 4 baseline warnings), fmt 5, lint 2, test 171, app 178,
"gate: PASS 370s". Then `RC_PROOF_APP=release cursor_layer_proof.py` on the integrated tree at
load average 32: **16/16**, L7 0.117 / 0.075 / 0.726 ms at 1920×1080 / 3840×2160 / 5120×2880,
`uploads` [1, 1], every other row's figures as the lane's, Z1 nothing in either launch's log.

**Owed.** No manual check (they need Separate recordings, CU3c). Cursor warnings on the Export
Queue row and the progress sheet are CU3b's (no person can attach a cursor file before it). L7's
figures are this Mac's under three lanes; the road map's limits are the owner's Mac's. Filed at
integration (`ai-drafted`, `low-priority`), found while checking every proof anchor in the files
this phase changed, not this phase's code: `qualifier_proof.py`'s `SHOWN` mutant anchor (`return
float4(float3(saturate(selected * coverage)), 1.0);`) is in no line of `Compositor.metal`, which
now spells `float3 grey = float3(saturate(selected * coverage));`, so the mutant cannot apply.

### CO2b — masks made on demand, and files that wait

- **What a person gets:** turning on a cutout starts the analysis of the windows its clips play; the
  picture redraws as each publish lands. An export waits for the masks it needs; `render_frame` and
  Save Frame wait briefly and say when a cutout was still pending.
- **Tolls first:** `Exporter.swift`'s `// MARK: - Offline single frame` (478–598) →
  `Exporter+Frame.swift`, carrying the `copyCGImage` deprecation (its `TYPECHECK_BASELINE` row and
  root `CLAUDE.md`'s "1 in `Exporter.swift`" sentence move with it);
  `EditorViewController+SaveFrame.swift`'s options (277–399) → `SaveFrameOptions.swift`.
- **Decisions (draft):** **CO-22 — Masks are made when a clip asks:** the document wants the
  analysed ranges its cut-out clips' windows need (a reversed clip's forward window, read mirrored
  from the one pack, CO-3), after every edit, at once (CO1's question, answered 2026-11-01, CO-15),
  from inside `ensureRampAudio()`.
- **Swift:** new `ProjectDocument+Masks.swift` (the wants, called by one line at the end of
  `ensureRampAudio()` in `ProjectDocument+RampAudio.swift`, so `ProjectDocument.swift` takes
  nothing; `.reversedMediaDidChange` when a publish lands); `Exporter+RampAudio.swift` (the mask
  wait inside `withRampAudio`, before its image-sequence guard, so image sequences wait too);
  `ExporterErrors.swift` (`cutoutFailed`); the export's mask wants released by one line in
  `releaseRecipeKey`; `Exporter+Frame.swift` (`renderFrameReported` takes a cutout wait, default
  none, waits up to it, reports the clips drawn uncut); `AgentServer+Render.swift` (`render_frame`
  passes 30 s and adds a sentence before its last); `EditorViewController+SaveFrame.swift` (30 s,
  then an informational sheet after saving naming the clip). The dev hold is CJ2a's
  `-RCDevAnalysisHold`.
- **MCP mirror:** `render_frame`'s description gains "a cut-out clip waits up to 30 s for its masks
  and is drawn uncut, and named, past that".
- **Docs:** spec §7.6 (the wants), §7.8 (the export waits), §7.9 (`render_frame`'s wait);
  `app/CLAUDE.md` (`ProjectDocument+Masks.swift`, the export's wait, `Exporter+Frame.swift`).
- **Acceptance:** proof rows against Release; `make gate`.
- **Proof** (`co2b_proof.py`): W1 `set_video {cutout}` makes the store's coverage hold every frame of
  the clip's window within the analysis time, and only those; W2 a trim that widens the window
  wants only the new range, the covered range's masks not rewritten; W3 with `-RCDevAnalysisHold`,
  `render_frame` returns after 30 s, draws the clip byte-identical to cutout off and names it, and
  without the hold waits and draws the cut picture; W4 an export started while masks are pending
  contains cut frames (decoded against `render_frame`'s); W5 a failing masks job fails the export
  with `cutoutFailed` naming the clip and leaves no file; W6 a reversed cut-out clip wants its
  forward window and draws the forward pack read mirrored; W7 the export's mask wants are gone
  after it finishes.
- **Mutants** (5): the export not waiting (W4); the wait outside `withRampAudio` (W4 on a PNG
  sequence); the want made only at open (W2); `render_frame` waiting without a bound (W3); the
  release line removed (W7).
- **Manual checks:** none. **Depends on:** CO2a. **Lane** C.
- **Question for the owner:** the preview draws a pending cutout uncut (CO-6)? *Recommended: uncut,
  with the Background status saying so* — a blank camera reads as a bug.

#### CO2b's record (2026-11-02)

**Landed.** Lane C, base `e18ef4b4` (I's HEAD, CO2a2). Commits: the toll alone
(`SaveFrameOptions.swift`, a pure move gated by `make typecheck`), then the decision with its
index row and the code, the proof and the documents, then this record. No format bump, no `rc_*`,
no core change. A clip whose base `video.cutout` is set now makes its own person masks: the
document wants its windows' missing ranges after every edit, sharing a running job that still
meets the need; a publish redraws the paused frame; an export waits for every mask it draws
(GIF and APNG too) and fails `cutoutFailed` when one cannot be made; `render_frame` and File ▸
Save Frame… wait up to 30 s and then name the clips drawn uncut.

| File | Lines | What |
|---|---|---|
| `app/Sources/SaveFrameOptions.swift` | 125 | the toll: Save Frame's accessory view, moved whole (`private` dropped) |
| `app/Sources/CutoutWants.swift` | 232 | `CutoutWindow`, the windows, the need rule, the keep rule, the requests, `CutoutWants.queue`, the dev log |
| `app/Sources/ProjectDocument+Masks.swift` | 84 | `ensureMasks()` (one owner per document, keyed by `recipeKey`) and `masksDidSettle()` |
| `app/Sources/Exporter+Masks.swift` | 173 | `waitForMasks`, `waitForFrameMasks`, `releaseMasks`, `cutoutSentences`, `frameCutoutWait` |
| `app/Sources/EditorViewController+Cutout.swift` | 19 | `analysisDidPublish(_:)`: a masks publish in this document's cache folder refreshes the paused frame |
| `AnalysisLane.swift` · `AnalysisStore.swift` · `ProjectDocument+Analysis.swift` | 348 · 272 · 90 | `requests(of:)`, `openRequests(kind:cacheDir:)`; `.analysisDidPublish`; the static `analysisRequest(…need:)` |
| `Exporter+Frame.swift` · `ExporterGraphics.swift` · `ExporterErrors.swift` · `Exporter+RampAudio.swift` · `Exporter.swift` | 147 · — · — · — · 491 | `cutoutWait`, `RenderedFrame.uncut`, `cutoutFailed`, the wait before the image-sequence guard, the release in `releaseRecipeKey`'s `ramp` |
| `AgentServer+Render.swift` · `AgentCatalog+Render.swift` · `AgentServer+AnalysisJob.swift` · `EditorViewController+SaveFrame.swift` | 330 · 438 · 201 · 308 | `render_frame`'s wait and sentence, its description, `mask_wants`, Save Frame's wait and sheet |

- **Deviations from the spec.**
  - `ProjectDocument.analysisInput` is marked `nonisolated` beside the new static
    `analysisRequest`: calling it from the nonisolated static was a fifth typecheck warning.
  - The editor refreshes only on a `masks` publish (`userInfo["kind"]`), not a `shots` one, which
    draws nothing.
  - `mask_wants` rows also carry `queued_at`, `started_at` and `ended_at`: W9 counts its runs from
    them, since `analysis_job`'s `jobs` lists only the dev owner's wants.
  - P1's freeze case is `freeze_frame`'s hold, which is one source frame (`[1,200,000,
    1,220,000)`, need 60…61), not zero-length; the zero-length window is P1's direct case
    (`[1,210,000, 1,210,000)`, need 60…61).
  - W4 holds the alpha to 1/255 and the colour as seen (each channel times its alpha) to 3
    levels: ProRes 4444's colour is lossy (the first run's worst was 1.98 levels; its alpha 1).
    W4b's APNG is held to 1/255 on every channel.
  - W9's export bound is 2,400 s (`LONG_EXPORT_BOUND`): a Debug run under three lanes' load
    passed 900 s (the rest of the 75 s analysis, then 75 s of ProRes 4444).

**Measured.**

- `make typecheck` exit 0 with the 4 baseline warnings after the toll and after the code;
  `swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS co2b_probe.swift` exit 0;
  `inventory.py --check` 5/5 (the Save Frame sheet's new site and the `frameSaved` anchors);
  `spec_index_proof.py` 240/240.
- `co2b_proof.py --only P1,P2` 2/2. On Debug (`make app-debug`): every row passed across three
  runs; W9 first failed its 900 s export bound and passed with the 2,400 s bound. W8's 75 s
  analysis took about 7 minutes on Debug under three lanes' load.
- `co2a_proof.py --only D2,D3,D4,D14` on Debug: 5/5 over the two launches.
- `make gate`: PASS 407 s (names 1, typecheck 7, fmt and lint skipped, test 244, app 154).
- `RC_PROOF_APP=release co2b_proof.py`: 14/14 — W1 coverage [[30, 90]] landed in 4.7 s; W2 the
  next document request [[15, 29]], coverage [[15, 90]], the 61 earlier blobs unmoved (76 now);
  W3b equal to the landed render and unlike cutout off, no sentence; W4 60 frames, (frame, worst
  premultiplied, worst alpha) (10, 1, 1), (30, 1.37, 1), (50, 1.98, 1), 207,128 pixels cut;
  W7 one export row, `wanted` false; W4b 50 APNG frames, worst 0 at frames 5, 25, 45; W5
  "Clip 3's person masks could not be made: the analysis could not be written: …", no file; W6
  forward window [10,800,000, 12,000,000), coverage [[540, 599]], 166,376 pixels hidden and
  5,165 uncut where the mask says, none differing; W8 the first mid-job publish at [[0, 1561]],
  the job [[0, 2249]] landed, coverage [[0, 2249]]; W9 the export's row is the document's
  running request [[0, 2249]], one run, the export done; W3 30.3 s, byte-identical, the sentence
  present; Z1 both launches empty.
- `RC_PROOF_APP=release co2a_proof.py`: 18/18 over the two launches (canned and held: D14's three
  frames and D3's two misses waited 30 s each and drew uncut; D2 and D4 in the second).
- `RC_PROOF_APP=release analysis_proof.py`: 22/22.
- Mutants, each once on Release in a tree copy (the tree's mutated files' SHA-256 unchanged):
  all eight CAUGHT, each app copy built in 153–202 s (M8's rows are the probe's, so it built
  no app). `M1-no-export-wait` W4 (worst 255 at the three frames: the export drawn uncut);
  `M2-wait-after-guard` W4b (worst 255 at frames 5, 25, 45); `M3-open-only` W2 (no document want
  after the cutout was set); `M4-unbounded-frame` W3 (`render_frame` past the 90 s bound);
  `M5-no-release` W7 (the export's row still `wanted`); `M6-kept-empty` P2 (the running and the
  queued-inside requests dropped) and W8 (the job [[0, 2249]] `cancelled` after the edit, a second
  one [[1394, 2249]] run); `M7-export-previous-empty` W9 (the export's own [[1391, 2249]] run beside
  the document's: two runs); `M8-queued-as-running` P2 (the queued 80…100 kept, the new request
  stopping at 79).

**Review.** One review (`e18ef4b4..e1bfb141`, three commits), verdict pass, every Files and
Approach item done, three nits, left as they stand:
- After a `.landed` wait that still leaves a media uncovered, the export wants the same request
  again under the same owner, and `AnalysisLane.want` resets an ended run only for a request not
  already in that owner's set. So CO-22 (e)'s second landing answers at once: it is a re-read of
  the store, not a second run, and the export then fails `cutoutFailed` ("its masks do not cover
  the frames it plays"). It fails safe.
- `ProjectDocument+Masks.swift`'s main-only table keyed by `recipeKey` keeps a closed document's
  small entry for the rest of the session, one per document opened.
- A failed document job is not retried until the clip's need changes: the re-want after
  `masksDidSettle()` equals the failed request, so the lane keeps its `.failed` outcome and the
  preview draws the clip uncut (CO-6) until an edit moves the window or the project reopens (once
  W5's folder is writable again, say). An export wants it under its own owner, so it runs again.

**Integration (2026-11-02).** Cherry-picked (`b9d63117…e1bfb141`) onto `worktree-creator-jobs`
at CU9a's `a99bf646`. Conflicts only in the decision file and the two indexes, each kept both
sides: `creator-jobs-4.md` holds CU9a's CU-90 block and then CO-22 (416 lines; its index row
416, both summaries), the `11-decisions/` folder cell 18691 in 38 files; no format, so nothing
renumbered. The owed `app/CLAUDE.md` edits went in: `Exporter+Masks.swift` in the Exporter
entry; `ensureRampAudio()` ending with `ensureMasks()` and the masks' wait before the build in
the RampAudio entry; the three files and the masks paragraph in the analysis entry; `+Cutout`
among the editor's extensions; `+SaveFrame`'s wait, its sheet and `SaveFrameOptions.swift`.
`spec_index_proof.py` 243/243; `inventory.py --check` 5/5; `make gate` PASS 316 s (names 1,
typecheck 7, fmt and lint skipped, test 154, app 152).

**Owed.** JOB-62 (`docs/manual-checks.md`): the owner's check that a paused picture redraws cut
without play. Nothing to file.

### TX4 — cuts the core can list and put back

- **What a person gets:** an agent can put back any cut a ripple made, or any part of one, as one
  undo step. The tab's button is TX5.
- **Room first:** `ReelProject.cuts()` goes in a new `ReelCore+Cuts.swift` (CJ-8 (l)). `ffi_query.rs`
  (392 of 400) takes nothing: the export gets its own module.
- **Decisions (draft):**
  - **TX-40 — A cut is where two clips of one file meet on a track with source skipped between
    them:** A ends exactly where B starts (no overlap; a transition is not a meeting); both are
    `media` sources of one media with the same `reversed`; equal speeds and neither ramped
    (`speed_map::is_ramped`; a ramp's source past its end is not what the cut removed); and `B.in >
    A.in + content_length_in_source(A)`. Its source is `[A.in + content_length(A), B.in)`. Its
    length `D` is the largest `t` with `at + t` on the canvas's frame grid for which
    `timeline_to_source(A.duration + t, speed) ≤ B.in − A.in` — the core's own rounding of the
    product a split makes, so for a ripple `D` is the removed span exactly at any speed and rate
    (29.97 fps's 20,020-tick frame and 7 fps's uneven grid included). `at` is A's end. Nothing is
    stored. Risk accepted: a cut that removed a whole clip, or where two different files met, is not
    a cut; undo brings it back, restore does not.
  - **TX-41 — `restore_cut {at, length, offset?}` puts back `length` of the cut material at `at`,
    starting `offset` into it (0 by default), as one op.** Snapped as `insert_time` snaps
    (`edit_time.rs:454–462`): a negative `length` or `offset` after snapping is an error, a zero
    `length` an identity. Per track, never rippling the timeline: (1) every clip on an unlocked
    track starting at or after `at` shifts right by `length` with its linked partner
    (`shift_clips`), and a clip straddling `at` stays put and whole; (2) on each unlocked track with
    a cut at `at` and `D_t > offset`, the piece is `L_t = min(length, D_t − offset)` long — with
    `offset` 0, A is extended into its handle by `L_t`; with `offset` above 0, a scratch copy of A
    is extended by `offset + L_t`, cut at `at + offset` by `split_clip`, and its second half (a
    fresh id) moved to start at `at`, so its `in`, base props and rebased actions are exactly what a
    ripple of the original's outer parts leaves; (3) when A and its linked partner both gain a
    piece, the pieces are linked by `pair_split_halves`' rule. The result equals the original with
    `[at, at + offset)` and `[at + offset + length, at + D)` rippled out, to the tick. Markers do
    not move. Locked tracks get nothing. A track with no cut at `at` gets a gap of `length` and its
    straddling clips (a music bed, a caption) keep every tick; a shorter cut is filled as far as it
    goes, then a gap. Refusals: "Nothing was cut at <at> ticks: no two clips of one file meet there
    with unused source between them." and "The cut at <at> ticks is <D> ticks long; offset <o> and
    length <l> reach past it." One op, not `insert_time` plus trims (which moves markers and would
    be two undo steps, AI-10).
  - **TX-42 — `rc_project_cuts(project)` answers every cut of the top-level container as JSON,**
    ordered by `at` then track order, each `{at, track, before, after, media, source_from,
    source_to, length}`; a scoped handle answers its nest's. Never NULL for a valid project (`[]`).
    Swift memoises it per handle as `sourceMap(_:)` is. Its shim is a new `core/src/ffi_cuts.rs`
    following `ffi_query.rs`'s rule (no handle allocated, no `err_out`).
- **Core:** new `cuts.rs` (`Project::cuts`, `D` through `timeline_to_source`), `edit_restore.rs`
  (composing `shift_clips`, `split_clip` on a scratch copy and `pair_split_halves`; no line of
  `edit_time.rs`), `ffi_cuts.rs`; `edit.rs` (variant, dispatch, module-doc row beside
  `insert_time`); `op_rows.rs` (`op("restore_cut", &[req("at", Ticks), req("length", Ticks),
  opt("offset", Ticks)])` after `insert_time`); `scope.rs` (allowed in a nest); `lib.rs`. Tests
  `core/tests/cuts.rs` and `restore_cut.rs`, the export in the null-safety sweep.
- **FFI:** `rc_project_cuts` (Rust, header, `ReelProject.cuts()` memoised).
- **Swift:** `ReelOps.restoreCut(at:length:offset:)`; the op tool's handler row in
  `creatorHandlers`, its body in `AgentServer+TimelineTranscript.swift` naming Clip ▸ Restore Words;
  its catalog entry in `AgentCatalog+Transcript.swift` declaring `scope`; `AssistantPrompt.swift`
  (`restore_cut` joins the "cut and time" topic's TOOL list; `assistant_prompt_proof.py`'s digest
  re-pinned (`make test` checks it)).
- **MCP mirror:** the op tool `restore_cut`, printed from the op table.
- **Docs:** spec §6b (beside `insert_time`; split by subsection first if past ~500), §7.1, §7.10;
  §11 TX-40…TX-42; `core/CLAUDE.md` (`cuts.rs`, `edit_restore.rs`, `ffi_cuts.rs`); `app/CLAUDE.md`;
  root `CLAUDE.md`'s product count.
- **Acceptance:** cutting a range and restoring it gives the same picture and sound on every track
  with a cut, at any speed and rate; markers unmoved; a clip no cut ran through is byte-unchanged.
- **Proof:** core tests K1 `ripple_delete_range` then `restore_cut(at, D)` gives back every unlocked
  track's plan segments; K1b at speeds 0.9, 1.1 and 1.00003 and at 29.97 and 7 fps, `D` equals the
  removed span; K2 markers unmoved; K3 a partial restore byte-equal (ids aside) to the original with
  the two outer parts rippled out, at speeds 1 and 1.1; K4 each refusal, a negative an error, zero
  an identity; K5 a locked track untouched; K6 a linked pair extended once each, and with `offset` >
  0 the pieces linked; K7 a ramp, a transition, a speed mismatch and a direction mismatch are not
  cuts; K8 a shorter cut filled as far as it goes; K9 inside a nest through `scope`; K10
  `rc_project_cuts`' shape and order; K11 a music bed laid across `at` after the cut, `offset` > 0:
  byte-unchanged; K12 a caption clip over `at`: byte-unchanged. MCP (`restore_cut_proof.py`, a 20 s
  fixture with microphone, camera and music): R1 export, cut, restore, export: PCM equal sample for
  sample and `render_frame` byte-equal at five times inside the span; R2 one undo step; R3 the
  tool's schema is the op table's.
- **Mutants** (8): a cut across different speeds; `D` by quotient and floor (K1b); markers moved; a
  locked track given a piece; a partner extended twice; the piece's `in` as two rounded products (K3
  at 1.1); the shift by `offset + length` with the gap rippled back (K11); a ramped clip counted.
- **Manual checks:** none. **Depends on:** TX1, CJ0b (T1), CJ0d (T15), CP1 recorded. **Lane** A.
- **Question for the owner:** when one track's cut is shorter than the restore asks, fill what each
  track has and leave a gap, or refuse? *Recommended: fill and leave the gap* (a refusal would block
  restoring speech over a trimmed music bed).

### CU3b — import and relink attach a cursor file

- **What a person gets:** a movie with `<stem>.fjcursor` beside it imports with its cursor; Relink
  keeps or replaces a recording's cursor file; a Cursor section in the Picture sub-tab with one row,
  Show cursor, for a clip whose media has cursor data and is not `in_picture`.
- **Swift:** new `MediaImporter+Cursor.swift` (a video probe looks for `<stem>.fjcursor` beside it;
  if it opens through `ReelCursor` and its `movie_size` equals the movie's natural size, the
  descriptor carries `cursor` with the header's `in_picture`); `MediaImporter+Probe.swift` (one call
  line); relink's probe carries the file beside the new movie, else the current `cursor` when its
  file still resolves, else none (which clears it); `land_recording` gains `cursor` (a fixture file
  for its one segment) and the recorder choices as they land (`cursor` and `show_clicks` at CU3c,
  `keys` at CU6, CU10's three); new `VideoPane+Cursor.swift` registered in
  `ClipPane.makeSections()`.
- **MCP:** `land_recording`'s new arguments.
- **Docs:** spec §7.7; `screen-recording.md` ("The cursor"); `app/CLAUDE.md`.
- **Decisions (draft):** **CU-34** import attaches a file only when its `movie_size` matches the
  movie. **CU-38** relink keeps a resolvable cursor file when the new movie has none beside it.
- **Proof rows** (`cursor_layer_proof.py`, Release): I1 the fixture movie with its file imports with
  `media.cursor`, and a file whose `movie_size` differs is not attached; I2 relink to a copy without
  a file while the old resolves keeps it, with the old removed clears it, to a copy with a file
  replaces it; I3 `land_recording` with the fixture lands a screen clip that draws its cursor; I4
  (harness) the section shows for a clip with cursor data and not for one without or `in_picture`;
  L1 (granted; skipped by name) on CU1b's In-the-picture recording, a copy of its file with
  `in_picture` false attached by Relink: the overlay's tip against the burned tip ≤ 1.5 px p95.
- **Mutants** (4): the size check removed (I1); relink clearing a resolvable cursor (I2); the
  section shown without a file (I4); the section not registered in `makeSections()` (I4).
- **Acceptance:** the proof rows against Release; `make gate`.
- **Depends on:** CU3a; CU1b (for L1). **Lane** B.

### CO3 — Remove Background in the inspector and the menus

- **What a person gets:** a **Background** section in the Picture sub-tab after Chroma Key: Remove
  Background (checkbox), Background (Remove / Keep, for Behind Subject), Edge, Feather, Quality
  (only if CO-S1 kept Best) and Status ("Analyzing 42 %", "Ready", "No person found", "Failed:
  <reason>", and "Paused while playing" if CJ-S3 (b) chose the pause), with Analyze Now. Clip ▸
  Remove Background toggles the selection. One undo step each; no Analyzing sheet (CO-6).
- **Swift:** new `VideoPane+Cutout.swift` registered after `chromaSection()` (`ClipPane.swift:198`);
  Edge and Feather animate through actions; the checkbox, Quality and Background are base-only
  (`InspectorBinding+Writes.swift`'s `structural(video:for:)`); new `CutoutStatus.swift` (the status
  memo, after `IsolationCache.Memo`); the menu item in `clipMenu()` (`AppDelegate+Menus.swift`,
  :251–395 at `d0661e5d`) with its validator arm in new `EditorViewController+Cutout.swift`;
  `UIMenuTable.swift` and `inventory.json`.
- **MCP mirror:** `analyze_cutout {clips, wait}` (`AgentServer+Cutout.swift`, a `creatorHandlers`
  row; `AgentCatalog+Cutout.swift`), mirroring Status and Analyze Now: it wants each clip's
  analysed ranges and answers per clip `state`, `progress`, `quality`, `covered`, `ready`,
  `subject_found` and `centroid` (the mean centroid of the window's cached masks, read from
  `MaskPack`; moved here from CO1, CO-15), waiting up to `wait` seconds. `get_media_analysis`
  stays the per-media reader.
- **Docs:** `canvas-and-layers.md` (Remove Background), `menus-and-shortcuts.md`, `mcp.md`, the
  README highlight; spec §4.3b, §7.9e, §9; root `CLAUDE.md`'s product count; a `screens.py` screen
  for the section.
- **Decisions (draft):** **CO-30** the section's rows and order. **CO-31** `analyze_cutout`'s
  answer.
- **Acceptance:** proof rows; the screen captured; `make gate`.
- **Proof** (`co3_proof.py`, Release; the harness for the chrome): I1 the checkbox writes one
  `set_video {cutout}` step; I2 Status walks Analyzing → Ready on a fixture and shows "No person
  found" on the UI fixture; I3 Edge inside a selected action writes the action's end, Quality there
  is ⊘; I4 `analyze_cutout {wait: 60}` returns `ready` with every frame of the window covered; I5
  the menu item's checkmark follows a mixed selection; I6 `analyze_cutout`'s `centroid` equals the
  mean centroid of the clip's cached window read from `MaskPack` by the probe (CO3 is the
  centroid's only prover).
- **Mutants** (3): the section not registered (I1); Quality written to an end (I3); `analyze_cutout`
  answering before its window is covered (I4).
- **Manual checks:** none (the look is the harness's). **Depends on:** CO2b. **Lane** C.
- **Question for the owner:** a key equivalent for Clip ▸ Remove Background? *Recommended: none in
  this phase*; §9 is crowded and the checkbox is one click.

#### CO3's record (2026-11-02)

**Landed.** Lane C, base `acc4cbd7` (I's HEAD, CO2b; the worktree was made at CO2a2's `e18ef4b4`
and fast-forwarded to it first). The lane's commits — the decisions alone (`4be0cd40`, CO-30…CO-32
with their index rows), the code (`8ee8351f`), the proof, the screen and the documents
(`582463a9`), this record (`a2f8b274`) — landed on `worktree-creator-jobs` as one commit after
CJ3 (`d9e762fa`). The merge kept both phases: CJ-30…CJ-35 then CO-30…CO-32 in
`creator-jobs-4.md` and in `11-decisions/README.md` (its file row's summary carrying both);
`get_media_analysis`'s catalog sentence and `mcp.md` row keep CJ3's `faces` text with CO3's
masks sentence; §7.4 keeps CJ3's analysis row with CO3's new row; the spec index's folder total
(18904) and §7.9e's Lines cell (560) set from `wc -l`. No format bump, no `rc_*`, no core change. The Picture sub-tab's Background section, after Chroma Key, turns Remove
Background on and tunes it with its Status read live; Clip ▸ Remove Background toggles the
selection (no key equivalent, the owner's answer); `analyze_cutout` is the mirror of Status and
Analyze Now, with the mean centroid CO7 will read.

| File | Lines | What |
|---|---|---|
| `app/Sources/CutoutStatus.swift` | 374 | `CutoutState`, `CutoutClipStatus`, `CutoutStatus` (`Detail`, `canCutOut`, the status rule, `words`, `toggleOps`, `menuState`, `progress`, `centroid`, the main-only stamp memo) |
| `app/Sources/CutoutStatus+Memo.swift` | 161 | `CutoutStatus.Memo`: the held status and its 0.5 s ticker |
| `app/Sources/VideoPane+Cutout.swift` | 133 | `allCutoutable`, `allCutOut`, `cutoutSection(_:)` |
| `app/Sources/AgentServer+Cutout.swift` · `AgentCatalog+Cutout.swift` | 111 · 54 | `analyze_cutout` and its row |
| `EditorViewController+Cutout.swift` · `EditorViewController.swift` · `AppDelegate+Menus.swift` · `UIMenuTable.swift` · `inventory.json` | 79 · 1087 (+1) · 490 | the command, Analyze Now and the validator arm; the frozen file's one line; the menu item; their rows |
| `CutoutProps.swift` · `TypedPatches.swift` · `InspectorBinding+Writes.swift` · `ClipPane.swift` | 137 · 365 · 304 · 274 | `CutoutPatch`; `VideoPatch.cutoutPart`; the structural clause; the memo, the registration, the signature |
| `ProjectDocument+Masks.swift` · `AnalysisLane.swift` | 98 · 369 | `maskOwner`, `analyzeMasksNow()`; `retry(owner:)` |
| `AgentServer+CreatorJobs.swift` · `AgentCatalog+Analysis.swift` · `AssistantPrompt.swift` | — | the handler row, the off-main set and `cutoutTools()`; `get_media_analysis`'s sentence; the topic's tool list |
| `tools/proof/co3_probe.swift` · `co3_proof.py` | 431 · 602 | the instrument |

- **Deviations from the spec.**
  - I4 compares `covered == frames` with `get_media_analysis {media, kind: masks}` over the clip's
    NEED, not `{clip}`: CO-22's need holds the frame at the window's end its last tick can ask for
    (61 frames for a 2 s window), one more than `get_media_analysis {clip}`'s window (60); the
    first Debug run failed on exactly that.
  - Mutant `M7-failure-first` breaks objection 4's two guards together (any failed run of the
    media fails a clip, checked before `covered == frames`): with the meet-uncovered rule kept,
    moving the order alone cannot fail clip A (it has no uncovered index), and dropping the rule
    alone is masked by the order.
  - `analyze_cutout`'s `wait` defaults to 0 (the status now), written into CO-31 (b); the spec
    named no default.
  - `CutoutStatus.Detail` (the needs, coverage, pack, owner and cache folder a status was read
    from) is the internal record the ticker's progress and the tool's centroid read; `CutoutState`
    carries `isSettled` and `sameKind(as:)`.
  - I3's last press (the checkbox) is recorded but not applied in the probe: with mutant M2 the
    wrong op put up an app-modal error and hung the probe to its 300 s bound; the row now fails on
    its own check.
  - `creator-jobs-4.md` is 620 lines after CO-30…CO-32 beside CJ3's CJ-30…CJ-35, past the ~500
    split rule; the spec named it, so the split is the next phase's.

**Measured.**

- `make typecheck` exit 0 with the 4 baseline warnings; `swift_build.py typecheck --define
  FRAMEJOB_DEV_TOOLS co3_probe.swift` exit 0; `inventory.py --check` 5/5; `spec_index_proof.py`
  243/243; `name_residue.py` exit 0.
- `co3_proof.py --only I1,I3,I5,I6p,I8` 5/5; on Debug (`make app-debug`) 10/10 after I4's fix
  above. `screens.py --only 05i-clip-background` 6 pass of 6, 4 captures, 0 new problems.
- `make gate`: PASS 406 s (names 1, typecheck 7, fmt and lint skipped, test 239, app 159).
- `RC_PROOF_APP=release co3_proof.py` (the final instrument): 10/10 — I2 "Analyzing 0 %" held,
  "Ready" 0.3 s after landing, the screen recording `no_person` and "No person found"; I4 held
  `analyzing` with 0 of 61 covered, then `ready` 61 of 61 in one `{wait: 60}` call,
  `get_media_analysis` 61 over the need; I6 (766.682…, 682.797…) over 42 found frames, |Δ| 0;
  I7 B "Failed: the analysis could not be written: You don’t have permission to save the file
  “2.json” in the folder “masks”" beside A ready, then "Analyzing 14 %" 0.31 s after the call,
  then ready; Z1 both launches empty.
- On one Release instance: `op_argument_proof.py` 188/188, `phase9_proof.py` 249/249,
  `v2_menu.py --only H` 5/5, its parity log empty; `recording_probe.py --only catalog` 31/31;
  `RC_PROOF_APP=release analysis_proof.py` 22/22; `RC_PROOF_APP=release co2b_proof.py --only
  P1,P2,W1,W5` 5/5 (W1 landed in 11.6 s).
- Mutants, each once on Release in a tree copy (the tree's mutated files' SHA-256 unchanged), all
  eight CAUGHT, each app copy built in 154–156 s: `M1-unregistered` I1 (no `video.cutout`, no
  commit); `M2-no-structural` I3 (the checkbox's gutter ◆ "at end", its commit a
  `set_action_end` with `off: ["video.cutout"]`); `M3-early-answer` I4 (three `{wait: 60}`
  calls answered `analyzing`, 0 of 61); `M4-no-mixed` I5 (some → on); `M5-unscaled` I6 ((204.4,
  242.8) against (766.7, 682.8)); `M6-no-retry` I7 (Status still "Failed: …" after 2.38 s, B
  failed after `{wait: 60}`); `M7-failure-first` I7 (A `failed`); `M8-progress-over` I8 (0.800
  and 0.600).
- At integration, on the merged tree with CJ3: `spec_index_proof.py` 243/243 after the two Lines
  cells; `make gate` PASS 306 s (names 1, typecheck 7, fmt and lint skipped, test 149, app 148).

**Review.** Against the spec, the notes and the checks: every Files and Approach item done, the
deviations above accepted, verdict pass with three nits and no fix pass: (1) a progress-only tick
refreshes the Status read-out but not the shut section's header summary, which keeps the first
"Analyzing N %"; (2) the process-wide stamp memo also keeps a nil stamp, so a transient "Failed:
the media file cannot be read" outlives Analyze Now; (3) `analyze_cutout`'s 0.25 s poll recomputes
every clip's detail on main, settled ones included. All three are left in the code and filed as one
issue naming this commit.

**Owed.** No JOB row (the screen `05i-clip-background` is the section's look); the review's three
nits as that issue. The `CLAUDE.md` edits were applied at integration: the root's parity paragraph
counts one hundred and twelve product tools; `app/CLAUDE.md`'s analysis entry (the five new files,
the status rule, the memo, `maskOwner`, `analyzeMasksNow()`, `retry`, `analyze_cutout`), the
editor's `EditorViewController+Cutout` bullet, `VideoPane`'s +`Cutout` clause,
`InspectorBinding+Writes`' cutout clause and `CutoutProps.swift`'s `CutoutPatch`.

### TX5 — cut words greyed, and Restore Words

- **What a person gets:** the words a cut removed stay in the transcript, greyed, where they were. A
  long cut collapses to "⋯ 212 words cut (1:34)" and opens on a click; a cut with no words reads "⋯
  0.8 s cut". Selecting greyed words and choosing Clip ▸ Restore Words, or pressing Return, brings
  exactly those back as one step "Restore Words". Cuts made on the timeline, by Remove Silences and
  by Remove Filler Words show and restore the same way.
- **Decisions (draft):**
  - **TX-50 — The words a cut removed stay in the transcript, greyed, between the kept words around
    it:** for each cut of a heard clip (TX-42), the words whose source start lies in the cut's
    source span (R6-10's half-open test). Up to 40 words, or 20 s, inline; longer collapses. Each
    greyed word carries its restore numbers, `offset` and `length` in timeline ticks inside its cut,
    by TX-30's edge rule within the cut's material, on the frame grid; the cut's first word starts
    at exactly 0 and its last ends at exactly `D`, so restoring all of a cut is exact. A ramped
    clip's cut is not a cut (TX-40): its words are neither greyed nor restorable.
  - **TX-51 — Restore Words:** Clip ▸ Restore Words, or Return with greyed words selected, sends one
    `restore_cut` with the selection's offset and length, step "Restore Words"; an agent sends
    `restore_cut` with `get_timeline_transcript`'s `cuts[]` numbers. Restore never re-merges the
    halves; it leaves one extra clip per track. TR-11's prompt paragraph gains `restore_cut`, with
    its Amended line.
- **Swift:** new `TimelineTranscript+Cuts.swift` (greyed words from `ReelProject.cuts()` and the
  media's words, with TX-50's numbers), `TranscriptView+Restore.swift`; `AppDelegate+Menus.swift`
  (about 460 after T5: Clip ▸ Restore Words); `EditorViewController+Transcript.swift` (validator);
  `UIMenuTable.swift` and `inventory.json`; `AgentServer+TimelineTranscript.swift` (`cuts[]`);
  `AssistantPrompt.swift` (TX-33's paragraph; `assistant_prompt_proof.py`'s digest re-pinned (`make
  test` checks it)).
- **MCP mirror:** `restore_cut` with the read's numbers.
- **Docs:** `transcript.md`, `menus-and-shortcuts.md`; spec §4.3e, §9; §11 TX-50, TX-51, TR-11's
  line; `app/CLAUDE.md`; `docs/manual-checks.md` (JOB-12).
- **Acceptance:** what the tab restores equals `restore_cut` with the read's numbers; restoring a
  whole cut gives back the uncut placements, save the split.
- **Proof** (`transcript_restore_proof.py`, Release): G1 after Delete Words, `cuts[]` lists those
  words with their offsets; G2 restoring all gives `get_project`'s pre-cut source spans on every
  track with one extra clip each; G3 restoring the middle word of three equals cutting the outer two
  from the original, a music bed laid across the cut afterwards byte-unchanged; G4 a Remove Silences
  cut reads as a pause-cut token; G5 40 words inline, 41 collapsed; G6 "Undo Restore Words"; G7 Clip
  ▸ Restore Words through `perform_menu_item` equals `restore_cut` with the read's numbers.
- **Mutants** (4): the collapse threshold; the first and last greyed words not exactly 0 and `D`;
  greyed words from a clip not heard; the undo name.
- **Manual check:** **JOB-12** — restored words on S-TH1 sound and look as they did before the cut,
  with no glitch where the halves meet.
- **Depends on:** TX3, TX4. **Lane** A.
- **Questions for the owner:** (1) Restore's key? *Recommended: Return on a greyed selection, plus
  Clip ▸ Restore Words with no key equivalent.* (2) Inline up to 40 words? *Recommended: yes* (a
  longer cut is usually a removed take).

### CU3c — the recorder stops burning the pointer

- **What a person gets:** a Cursor row in the recorder panel: **Separate** (the default) or **In the
  picture** (today's behaviour). With Separate the pointer and click ring are not in the movie and
  Frame Job draws them. Show Clicks lands the clips with `cursor.clicks: ripple`.
- **Swift:** `RecordingChoice.cursor` (`.separate` | `.inPicture`); `RecordingConfiguration.make`
  sets `showsCursor`, `showMouseClicks` and BGRA only `.inPicture`; the file's `in_picture` follows
  the choice; the panel's popup and its remembered key `FrameJobRecordingCursor` (the twelfth;
  written on change, restored on show; the harness and `screens.py` pin it, AU-69 (b)); the landing
  writes `set_video {cursor: {clicks: "ripple"}}` on the screen clips when Show Clicks is on and
  Cursor is Separate, inside the landing's grouped edit.
- **MCP:** `record_screen` gains `cursor` (`"separate"` default, `"in_picture"`), refused by name
  with `voice_over` and `camera`; `show_clicks` keeps its meaning per mode.
- **Docs:** `screen-recording.md` (the panel, the cursor); the README's screen-recording highlight;
  spec §7.9d; `docs/manual-checks.md` (JOB-21, JOB-27, JOB-28).
- **Decisions (draft):** **CU-31** the stream's cursor and ring only In the picture (restating "Show
  Clicks needs BGRA"; with Separate, Show Clicks means "land the clips with ripples on"). **CU-36**
  Separate as the default (In the picture if CU-S2's Separate rows failed), the key, the tool
  argument.
- **Acceptance:** the probes and `land_recording` rows pass; a granted Separate recording has no
  burned cursor and draws one in the editor.
- **Proof rows:** *ungranted:* B2 (probe) `RecordingConfiguration.make` In the picture is
  byte-for-byte today's configuration (`recording_probe.py`'s fields), and with Separate
  `showsCursor` and `showMouseClicks` are false and the format 420v; B3 `land_recording` with
  `cursor: "separate"` and `show_clicks: true` lands `clicks: ripple`; B5 `record_screen {source:
  "voice_over", cursor: "separate"}` refused by name. *Granted* (skipped by name): B1 a Separate
  recording's frames with `show: false` hold no cursor pixels against the flat backdrop; B4 a
  Separate recording of CU-S2's moving square: the drawn cursor against the square's corner ≤ 1.5 px
  p95 and ≤ one frame.
- **Mutants** (4): `showsCursor` left true with Separate (B2); BGRA with Separate (B2); the ripple
  write skipped (B3); the argument not refused with `voice_over` (B5).
- **Manual checks:** **JOB-21** — the drawn cursor on a real Separate recording looks like the
  system's own, at 1× and on Retina. **JOB-27** — a real window recording dragged and resized while
  recording keeps its cursor on the pointer (S-ST4). **JOB-28** — with a second display, a recording
  of one display shows no cursor while the pointer is on the other (S-ST5; skipped with one
  display).
- **Depends on:** CU3b, CU1b. **Lane** B.
- **Question for the owner:** the default? *Recommended: Separate* — the bet's point, with In the
  picture one click away — unless CU-S2's Separate rows failed.

### CO4 — edges

- **What a person gets:** the outline follows hair and shoulders more closely (CO-S3's refinement),
  the same in SDR and HLG projects, and Best quality if CO-S1 kept it.
- **Head:** CO-S3 runs if it did not at CO0 (S-KEY1 needed; without it r0 ships and the row is
  owed).
- **Core:** nothing unless CO-S3 needs a constant in the recipe; CO-40's constants live in the
  shader.
- **Swift:** `Compositor.metal` (r1 in the layer stage) or new `Compositor+Cutout.swift` (r2's
  pre-pass before the destination opens, as the matte pass is); `ChromaKeyHDR.swift`'s `KeyReading`
  passed to the refinement (CO-7); the `masks_best` kind and the Quality row if Best exists.
- **MCP mirror:** none new.
- **Docs:** spec §7.5b; `canvas-and-layers.md`; `docs/manual-checks.md` (JOB-60).
- **Decisions (draft):** **CO-40** the refinement CO-S3 chose and its constants. **CO-41** Best's
  default: off.
- **Acceptance:** CO-S3's B reproduced within 10 %; `make gate`.
- **Proof** (`co4_proof.py`, Release): E1 B on S-KEY1's composites at 1080p within 10 % of CO-S3's;
  E2 the same in an HLG project within 2 %; E3 `play_preview`'s count within CO-S3's cost bound; E4
  Edge −1 and +1 move the 0.5 contour inward and outward by the documented amount at 1080p.
- **Mutants** (3): the guide read without `KeyReading` (E2); the refinement skipped in the shadow
  pass (E1's shadow row); Edge's sign reversed (E4).
- **Manual check:** **JOB-60** — on S-TH1, S-TH2 and S-TH5, at Standard and Best: hair, hands in
  motion, glasses, the outline against a busy room. The verdict decides whether a matting-model
  candidate is filed (CO-1).
- **Depends on:** CO2a, CO3. **Lane** C.
- **Question for the owner:** Best as the default on a short clip? *Recommended: Standard always,
  Best chosen per clip.*

### TX6 — the review pass: long pauses and fillers

- **What a person gets:** Review, in the tab's bar, strikes long pauses (over 1 s, keeping 0.2 s at
  each end) and, with an AssemblyAI filler transcript, filler words. Each strike shows in the text
  and as the timeline wash; a click keeps one. Clip ▸ Remove Struck, or the bar's button, cuts every
  strike still standing as one step "Remove Struck", the bar saying first how many and how much
  time; a removal past `RC_MAX_CLIPS` is refused with the count it would make. Every media with a
  filler transcript is struck, key or no key; the others are listed, with Transcribe… when the
  AssemblyAI key is set; only with no key and no filler transcript at all is the Fillers box greyed,
  `ModelKeys`' sentence its tooltip.
- **Decisions (draft):**
  - **TX-60 — The review pass strikes long pauses and, where a filler transcript exists, filler
    words; Clip ▸ Remove Struck cuts what is still struck, as one step.** Pauses:
    `SilenceDetector.detect` in voice mode (level mode where the model cannot run), scoped to the
    shown clips, shortest 1.0 s, 0.2 s kept each end. Fillers: `FillerDetector.detect` (TR-9) over
    shown clips whose media have a filler transcript. The detectors' walls stand. Strikes show in
    place and as the candidate wash while the tab shows strikes; the pane sets its wash again on
    every refresh and when a sheet ends (`NSWindow.didEndSheetNotification`), so a Remove Silences
    or Remove Filler Words sheet opened and closed leaves it. A kept strike is view state per
    window, kept across edits by word identity. Remove Struck sends one `ripple_delete_ranges` of
    the remaining items, merged, with TX-32's cap check.
  - **TX-61 — `review_transcript {from?, to?, tracks?, pauses?, min_pause?, keep?, fillers?,
    retakes?, language?}` answers what the review strikes and cuts nothing** (TR-4's read half):
    `items[]` (`kind` pause, filler, restart, retake or repeat; `start`, `end`, `words`, `reason`;
    `of`, the kept take's start, for a repeated phrase), `ranges` (merged, ready for
    `ripple_delete_ranges`), `count`, `removes`, `dropped[]` with reasons, `needs_transcript[]`,
    `clips_after` (TX-32's count with `ranges` applied, and the cap sentence past `RC_MAX_CLIPS`).
    `fillers: true` is refused through `ModelKeys.require(.assemblyAI)` only with no key and no
    filler transcript in scope. Remove Struck's edit is ONE op, so an agent's `review_transcript`
    then one `ripple_delete_ranges` of `ranges` (less any it keeps) makes the tab's single step
    through the same planner (CJ-8 (f)); a tool that cut in the same call would skip the review.
  - **TX-62 — Filler strikes follow TX-14.** Media without a filler transcript are listed under
    "Fillers need an AssemblyAI transcript"; with the key the list carries Transcribe…, which opens
    Clip ▸ Remove Filler Words… (whose rows show the price and send the upload, TR-10), without it
    `ModelKeys.sentence(.assemblyAI)`. The assistant still cannot start a paid upload (AI-7, TR-10).
- **Swift:** new `TranscriptReview.swift` (pure: kinds, merge, item identity, kept strikes),
  `TranscriptReview+Sources.swift`, `TranscriptBar+Review.swift`,
  `AgentServer+TranscriptReview.swift`; `AppDelegate+Menus.swift` (Clip ▸ Remove Struck after Remove
  Filler Words…, :324); `UIMenuTable.swift` and `inventory.json`;
  `EditorViewController+Transcript.swift`; `TranscriptPane.swift` (sets
  `TimelineView.candidateSpans` on refresh and when a sheet ends, clears it when the tab hides;
  `TimelineView.swift` takes nothing); `AgentCatalog+Transcript.swift` (`review_transcript`, its
  description carrying the key clause for `fillers`, CJ-13); `AgentServer+CreatorJobs.swift`;
  `AssistantPrompt.swift` (`review_transcript` joins the "audio: find silences and filler words…"
  topic's TOOL list; TX-33's paragraph gains its sentence, with its Amended line;
  `assistant_prompt_proof.py`'s digest re-pinned (`make test` checks it)); `ModelKeys.swift`
  (`keyed` gains `review_transcript` as a conditional keyed tool; the Fillers box through its
  control helper).
- **MCP mirror:** `review_transcript`, then `ripple_delete_ranges`.
- **Docs:** `transcript.md`; `cleanup-tools.md` (links both ways); `menus-and-shortcuts.md`;
  `mcp.md` (with its key clause); spec §4.3e, 07.9f, §9; §11 TX-60…TX-62; the screen
  `designs/screens/11d-transcript-review.md`; `app/CLAUDE.md`; root `CLAUDE.md`'s app-state tool
  list and product count; `docs/manual-checks.md` (JOB-13).
- **Acceptance:** the review's pause and filler items equal the two detectors' answers under the
  review's settings; Remove Struck equals `ripple_delete_ranges` of what is still struck.
- **Proof** (`transcript_review_probe.swift`, `transcript_review_proof.py`, Release; every row with
  `-RCSecretFolder` on an empty folder and `RC_ASSEMBLYAI_KEY` unset; V3's keyed rows with the
  dummy-key folder and `assemblyai_fake.py`): V1 a `say` fixture with 1.5 s planted pauses: every
  pause struck, ranges equal `SilenceDetector`'s at 1.0 s and 0.2 s; V2 fillers from an
  `assemblyai_fake` cache equal `detect_fillers`'; V3 with no key and no filler cache the box is
  disabled with the sentence as its tooltip (read through `transcript_view`) and `fillers: true` is
  refused with it; with no key and one of two media cached the box is enabled, that media's fillers
  struck, the other under `needs_transcript` with the sentence and no Transcribe…, the stand-in
  recording zero requests; with the dummy key the box is enabled and Transcribe… offered; V4 a kept
  strike is left out of Remove Struck; V5 one step "Undo Remove Struck" whose placements equal
  `ripple_delete_ranges` of the read's ranges less the kept; V6 the cap sentence on a fixture the
  removal would take past `RC_MAX_CLIPS`, no step; V7 the wash equals the strikes while the tab
  shows them and clears when it hides; V7b Remove Silences… opened and cancelled leaves the wash
  equal to the strikes; V8 Remove Struck of 600 ranges over four tracks timed and recorded, not
  capped.
- **Mutants** (8): the 0.2 s kept ignored; the 1.0 s shortest off by a frame; fillers enabled with
  neither key nor cache; fillers struck only when every media is cached (V3); kept strikes removed
  anyway; the wash not cleared; the wash not restored after a sheet (V7b); fillers merged past their
  walls.
- **Manual check:** **JOB-13** — Remove Struck on S-TH1: the pace after it sounds natural.
- **Depends on:** TX3, CJ1 (TX5 soft: removed items show greyed). **Lane** A.
- **Questions for the owner:** (1) Long pause at 1.0 s, keeping 0.2 s each end? *Recommended: yes*
  (Remove Silences' 0.5 s is a tighter cut for a sheet a person tunes; a review strikes only what is
  clearly dead air). (2) Strikes on the timeline as a wash? *Recommended: yes.*

### CU4 — the Cursor section, and what a recording lands with

- **What a person gets:** the Cursor section in the Picture sub-tab grows to Show cursor, Size
  (25–800 %), Style (As recorded, Arrow), Smoothing (Off … Strong), Hide when idle (Never, 1–10 s),
  Clicks (None, Ripple) with Ripple colour and Ripple size. Each row is undoable; Size and Ripple
  size are keyable; Show, Style, Clicks and Ripple colour switch at an action's end; Smoothing and
  Hide when idle are the clip's (⊘ inside an action).
- **Core:** `style: arrow` draws Frame Job's own vector arrow at the image's size, no Apple artwork
  (a fixed SVG rasterized by the graphic engine once per size, or a bundled 256 px PNG; settled at
  the phase's design pass).
- **Swift:** `VideoPane+Cursor.swift` grows to the full section;
  `InspectorBinding+Writes.structural(video:)` routes `cursor.smoothing` and `cursor.hide_idle` to
  the base (CU-30); Paste Attributes carries `video.cursor`.
- **MCP:** `set_video`'s prose names every key; nothing new.
- **Docs:** `screen-recording.md` ("The cursor"), `canvas-and-layers.md`, spec §4.3b;
  `app/CLAUDE.md`'s `InspectorBinding+Writes.swift` entry; `docs/manual-checks.md` (JOB-22).
- **Decisions (draft):** **CU-40** the rows and their ranges. **CU-41** the Arrow style's source.
  **CU-42** the look a recording lands with (the question below).
- **Proof rows:** S1 each row's op read back; S2 Size 200 % doubles the sprite's drawn bounds (±1
  px); S3 Hide when idle 2 s: no cursor pixels 2.3 s into a still stretch, and the cursor back 0.15
  s before the next movement; S4 Smoothing Strong passes through every click position at its time (≤
  0.5 px); S5 (probe) with an action selected, Smoothing writes the base, never the end.
- **Mutants** (3): smoothing routed into the end (S5); the size row writing `click_size` (S1); Arrow
  ignored (S2 against the arrow's bounds).
- **Manual check:** **JOB-22** — smoothing and idle hide look natural on a real recording.
- **Acceptance:** the proof rows against Release; `make gate`.
- **Depends on:** CU3b. **Lane** B.
- **Question for the owner:** the look a recording lands with? *Recommended: as captured, plus
  ripples when Show Clicks is on*; the polished look (smoothing 0.5, hide after 3 s) is one click in
  the section, or CU10's landing option, not a silent default.

### CO5 — Text Behind Subject

- **What a person gets:** Insert ▸ Text Behind Subject puts a title on a new track directly above
  the cut-out clip at the playhead, already behind the person. Any drawing clip can be put behind
  with a **Behind Subject** section. A camera whose background is kept still hides the title behind
  the person.
- **Decisions (draft):**
  - **CO-50 — Behind Subject is a per-instant relation, drawn by the matte machinery.**
    `video.behind_subject: true` (format p) on any drawing clip but an adjustment or nest clip. At
    each instant the clip is cut by the SUBJECT of every layer with a cutout behind it in its own
    container — walking that layer's levels outward (MT-5's walk), it reaches the behind clip's
    container on a track behind the behind clip's track. No clip names another, so no edit breaks
    it. The core emits each subject as a matte group of mode `alpha_inverted`, drawn by a COPY of
    the cut-out layer with `background: remove`, `blend: normal`, `shadow: null`, `reflection:
    null`; the copy sits in `layers` beside its original with `matte.into` set, so the canvas hit
    test is unchanged. The behind clip's own shadow is cut with it (MT-3). A boolean, it switches at
    an action's end.
  - **CO-51…CO-54:** the subject copy as MT-4's third override; `background: keep`; Insert ▸ Text
    Behind Subject's planner (`add_track` above the clip's track, `add_text_clip` with the Title
    preset at the playhead for min(4 s, the clip's rest), `set_video {behind_subject: true}` and,
    when the clip has no cutout, `set_video {cutout: {background: keep}}`, one step); its tool
    `text_behind_subject`, running the same planner.
  - Amendments: **MT-1** "A matte group can also be a clip's SUBJECT (CO-50): drawn by a copy of a
    cut-out layer, never by a track; only a track makes a clip a matte." **MT-2** "A clip with
    `video.behind_subject` is cut by the subjects behind it as well as by any matte in front of its
    track; the cuts multiply." **MT-4** "A subject copy is the third deliberate override: emitted
    with `background: remove`, `blend: normal`, `shadow: null`, `reflection: null`."
    (`core/CLAUDE.md`'s "TWO deliberate overrides" and spec §7.3 change with it.)
- **Core:** `video.behind_subject` with its checks in `cutout_check.rs`; new `recipe_subject.rs`
  (which cut-out layers are behind each behind clip at `t`, the subject copies, their groups merged
  into `matte` and `mattes` with dense ids, MT's id rule), one call from `recipe.rs`; the format
  bump (`format_history.rs`' toll first if it would pass 400) and `core/tests/behind_subject.rs`.
- **FFI:** the bump's `#define`.
- **Swift:** `MattePlan.swift` schedules subject groups as matte groups; new
  `BehindSubjectPlan.swift` (the planner, pure over a snapshot and a playhead); new
  `EditorViewController+BehindSubject.swift` (Insert ▸ Text Behind Subject through
  `performGroupedEdit`, its validator); the item in `AppDelegate+GraphicMenu.swift`;
  `UIMenuTable.swift` and `inventory.json`; new `VideoPane+BehindSubject.swift` (the checkbox, and a
  note when no cut-out clip is behind at the playhead), registered after Transform.
- **MCP mirror:** `text_behind_subject {clip?, at?, content?}` (`AgentServer+BehindSubject.swift`, a
  `creatorHandlers` row; `AgentCatalog+BehindSubject.swift`) runs `BehindSubjectPlan` as one undo
  step, naming Insert ▸ Text Behind Subject; `set_video`'s description names `behind_subject`.
- **Docs:** spec §5.2a, §7.3, §7.9e, §9; `canvas-and-layers.md`, `menus-and-shortcuts.md`, `mcp.md`;
  `core/CLAUDE.md`; `mattes.md`'s amendments; `docs/manual-checks.md` (JOB-62); root `CLAUDE.md`'s
  product count.
- **Acceptance:** proof rows; `make gate`.
- **Proof** (`co5_proof.py`, Release; canned bar-code masks and a real person fixture): B1 where the
  subject's mask is 255 over a 3×3 texel neighbourhood the behind title's pixels are absent, and
  where 0 present; B2 a title in FRONT of the camera's track with the flag set is cut only by
  subjects behind it; B3 a split, a move and an undo of the camera keep the cut; B4 `background:
  keep` draws the camera whole and still cuts the title; B5 the title's shadow is cut with it; B6 a
  frame with no behind clip lists no subject group; B7 `play_preview` of a behind title over a
  cut-out 1080p camera composes ≥ 95 % of the frames composed with the flag off; B8
  `text_behind_subject` and the menu make the same project, each one step.
- **Mutants** (4): subjects taken from tracks in front (B2); the copy drawn with the camera's shadow
  (B5); the group listed without a cut layer (B6); the tool applying three steps (B8).
- **Manual check:** **JOB-62** — on S-TH1, a title behind the owner: no visible halo or gap where
  the soft edge meets the letters.
- **Depends on:** CO2b, CO4. **Lane** C.
- **Question for the owner:** a clip flag or a track flag? *Recommended: a clip flag* — a title is
  placed per moment, and a track flag would catch every later clip on the track.

### TX7 — retakes, restarts and repeats

- **What a person gets:** the review also strikes an earlier take of a line said again, a phrase
  broken off and restarted, and a word or a few said twice in a row. Each strike names what it
  repeats ("An earlier take of 'So today we're going to…', kept at 02:14"); the last take is kept.
  No key is needed. "Find more with the Assistant…" puts a request for false starts that repeat
  nothing into the Assistant's message field for the person to send; it is greyed without an
  Anthropic key.
- **Head:** TX-70 (recorded at CJ0a) is checked to stand; TX-S4 runs; TX-71 records its setting.
- **Decisions (draft):**
  - **TX-71 — The retake rule's numbers.** A phrase ends at sentence punctuation, a pause of P s
    (voice cache) or a change of clip; a retake compares a phrase with the next K phrases within 30
    s, at a similarity θ (the longest common subsequence of normalised tokens over the earlier
    phrase's length) and a shortest phrase of four tokens; a restart needs an exact token prefix of
    at least two tokens, or the whole earlier phrase when it has one or two; a one-word repeat
    counts only when a pause separates the two words. Defaults before the spike: P 0.6, K 3, θ 0.6;
    TX-S4's rule sets them and may ship retakes off by default. The splitter is the shared one (CJ-8
    (j)), pure and parameterised, which FC4 calls.
  - **TX-72 — "Find more with the Assistant…" puts a request in the Assistant's message field and
    sends nothing:** "Find false starts in the transcript between <from> and <to> that repeat no
    words, tell me which words, then cut them." The button shows the Assistant tab; the person
    presses Return to spend. Without the Anthropic key it is disabled with
    `ModelKeys.sentence(.anthropic)` as its tooltip (CJ-12's Assistant row). No tool, no AI-7 row.
- **Swift:** new `RetakeFinder.swift` (pure: tokens, the phrase splitter, the three rules, chains
  kept last); `TranscriptReview.swift` (the three kinds); `AgentServer+TranscriptReview.swift`
  (`retakes`); `TranscriptBar+Review.swift` (the box and the hand-off);
  `EditorViewController+Assistant.swift` (`prefillAssistant(_:)`, showing the tab and setting the
  composer without sending); `AssistantView.swift` (the composer's setter); `AssistantPrompt.swift`
  (the false-start sentence, with TX-33's paragraph's Amended line; `assistant_prompt_proof.py`'s
  digest re-pinned (`make test` checks it)).
- **MCP mirror:** `review_transcript {retakes}`. The hand-off is a person's button with no tool.
- **Docs:** `transcript.md`; `cleanup-tools.md` ("Cutting false starts with the assistant" says
  repeats are found in the tab); `assistant.md` (the hand-off); spec §4.3e; §11 TX-71, TX-72;
  `app/CLAUDE.md`; `docs/manual-checks.md` (JOB-14, JOB-15).
- **Acceptance:** on the `say` twin of S-RT1 the pass meets TX-71's recall and strikes no trap word;
  the proof against Release; `make gate`; then one paid prompt eval
  (`assistant_prompt_eval.py --live --cap 1.00`, the month's budget, its dollars in the record),
  since TX3–TX7 rewrote the prompt's "Cutting words" paragraph that TX8 and JOB-15 lean on.
- **Proof** (`retake_probe.swift`, `retake_proof.py`, Release): Q1 the answer key on the `say` twin:
  every restart and repeat struck, retakes at TX-71's recall, no trap word; Q2 (probe, word lists) a
  chain of three keeps the last; fillers are ignored; different speakers are never compared; a
  retake across a clip boundary on one track is found; a duplicated clip and a hook copied to the
  open are never struck; Q3 `review_transcript {retakes: true}` equals the probe's items; Q4 the
  hand-off greyed with the Anthropic sentence with no key (`-RCSecretFolder` empty,
  `ANTHROPIC_API_KEY` unset), and with the stand-in's dummy key it fills the composer and no turn
  starts; Q5 the pass runs with no key at all.
- **Mutants** (7): θ off by 0.1; the window at 1; keep-first; fillers counted as tokens; one-word
  repeats without the pause rule; different speakers compared; the same source compared with itself.
- **Manual checks:** **JOB-14** — retake strikes on S-TH1 and S-ST1: the kept take is the one
  wanted; a wrong strike is noted with its time. **JOB-15** — the hand-off with a real key: the
  Assistant names its cuts before cutting (as AS-10 checks).
- **Depends on:** TX6, CJ1; TX-S4 at its head (S-RT1). **Lane** A.
- **Questions for the owner:** (1) Retakes on by default? *Recommended: on if TX-S4's rule passes on
  your read, else off, with restarts and repeats on.* (2) The hand-off button? *Recommended: yes* —
  it costs nothing until you press Return. (3) TX-S4's AssemblyAI read of S-RT1 (about a cent, cap
  $0.05, only your own voice)? *Recommended: yes* — it tests the rule on the transcript the
  Transcript tab shows when words come from AssemblyAI; with a no, the rule is set on the two
  on-device reads and the AssemblyAI row is owed.

### CU5 — cursor data travels

- **What a person gets:** Consolidate Media copies each cursor file into the package beside its
  movie; the Media tab names a recording's cursor file, says when it is missing, and offers Locate…
  and Remove; agents read a recording's clicks, shortcuts, typing stretches and smoothed path.
- **Core:** new `media_cursor.rs`, `set_media_cursor {media, cursor: {path, bookmark?, in_picture} |
  null}`, refused on a non-video media and on an empty path, each in its own sentence; in
  `scope.rs`'s `refused_inside` beside `set_media_speech`, and in `ReelOp.documentLevelNames`; the
  `op_rows.rs` and `edit.rs` rows. No format change.
- **Swift:** `MediaConsolidator` plans each cursor file as a second copy (the claimed-name rule, the
  stem of the movie's destination) and emits `set_media_cursor` after the movie's `relink_media`,
  only once both copies are on disk; `ProjectDocument+MissingCopies.swift`'s `repairingMedia` gains
  the cursor re-anchor (a `media.cursor.path` resolving to nothing, with a same-named file in
  `media/`, is re-pointed; `ProjectDocument.swift` takes no line); new `MediaPane+Cursor.swift`.
- **MCP:** `set_media_cursor` (op tool); `get_cursor_events {media | clip, from?, to?, kinds?}`
  (`AgentServer+Cursor.swift`, `AgentCatalog+Cursor.swift`, `scope` declared, a `creatorHandlers`
  row) answering, in clip or media time, clicks with their position in source pixels and in the
  clip's region frame Q (so a region goes straight to `add_zoom_action`), scroll bursts, shortcuts,
  typing stretches, and with `kinds: ["path"]` the smoothed path at most 10 Hz; paged at 5,000
  events; a reversed clip in clip time refused by name (CU-5).
- **Docs:** `projects-and-media.md`; `screen-recording.md`; `mcp.md`; spec §6c, §7.9d;
  `core/CLAUDE.md`; `app/CLAUDE.md` (`documentLevelNames`' count); the counts of CJ-8 (g).
- **Decisions (draft):** **CU-50** `set_media_cursor`, document-level. **CU-51** Consolidate's
  second copy and its order. **CU-52** the open-time re-anchor. **CU-53** `get_cursor_events`'
  answer.
- **Acceptance:** a consolidated project with its originals moved away still draws its cursor.
- **Proof rows:** M1 consolidating a recording puts both files in `media/` and `get_project` shows
  both paths inside the package; M2 a moved package reopened is re-anchored; M4 `get_cursor_events`
  on a fixture: counts and Q positions equal the fixture's, `path` equals CU2's T4; M5 a failed
  cursor copy leaves the media pointing at the original; M6 `set_media_cursor` with a `scope`
  refused (core test and tool); M7 `get_cursor_events {clip}` on a reversed clip refused by name.
- **Mutants** (4): `set_media_cursor` emitted before the copy lands (M5); the re-anchor not run
  (M2); Q without the crop (M4); `set_media_cursor` left out of `refused_inside` (M6).
- **Depends on:** CU3b. **Lane** B.

### CO10 — cutout on stills and pictures

- **What a person gets:** Remove Background and Behind Subject on a photo, which may cut its
  foreground object, not only a person. (A freeze frame already cuts through its video's masks,
  CO2a's D11.)
- **Decisions (draft):** **CO-100 — Stills and images take a foreground subject** (format p):
  `CutoutSubject::Foreground`, accepted on image clips only, refused on a media or still clip by
  name (CO-1); the recipe's `cutout.mask` arm `{kind: "image", media}`.
- **Core:** the subject, the arm, the format files as in CO2a.
- **Swift:** `AnalysisMasks.swift`'s still arm (one mask per image, a run at tick 0 in CJ-22's
  store, the request by subject), bound at `texture(4)` by `LayerRenderersImage.swift`'s layer; the
  section's Subject pop-up for pictures.
- **MCP mirror:** `set_video`'s description.
- **Docs:** `canvas-and-layers.md`; `docs/manual-checks.md` (JOB-65).
- **Proof** (`co10_proof.py`, Release): S1 a person still cut with `person` and a pencils still with
  `foreground` make the masked pixels the background; S2 `foreground` on a media clip refused.
- **Mutants** (1): `foreground` admitted on media (S2).
- **Manual check:** **JOB-65** — a portrait photo's cutout edge on hair.
- **Acceptance:** the proof against Release; `make gate`.
- **Depends on:** CO4. **Lane** C.
- **Question for the owner:** build pictures in this road map? *Recommended: yes, last*; it can be
  filed instead without touching CO0–CO9.

### TX8 — CJ-5's closing trial run

- **What a person gets:** a recorded verdict on whether the tab does a real edit, and the residue as
  issues. No product code, unless the verdict asks for a fix, which is then TX9, sized after.
- **The run:** the owner cuts S-TH1 and S-ST1 again, as at the baseline, so the runs compare;
  recorded in CJ-5's form in "The owner's trials", the verdict under CJ-5 ("**Verdict (owner,
  date):** …") and TX-80 holding only "Recorded under CJ-5, <date>."
- **This bet's figures beside CJ-5's criteria** (agreed before TX1's code): the tab's part in the
  cut (words deleted, at least one cut restored, the review run and what it removed); with a key,
  one false start the pass missed, found through the hand-off; `transcript_verdict.py measure`'s
  figures on the two projects (the first fill's time against the recording's length, the rebuild
  time after a cut, Remove Struck's time, the clips after the edit against `RC_MAX_CLIPS`); and
  `transcript_verdict.py sizes` against the bet's base commit (frozen files changed by wiring only,
  no file over the cap unpaid).
- **Residue:** filed `ai-drafted` and `low-priority`.
- **Proof:** `transcript_verdict.py`, against Release, on the owner's projects read in place.
- **Mutants, manual checks:** none (the trial is CJ-5's, not a JOB row).
- **Depends on:** TX7. **Lane:** beside A (CJ5b goes on).
- **Question for the owner:** are these figures the right ones? *Recommended: yes, as stated, agreed
  before TX1's code.*

### CJ5b — File ▸ New Project from Range…, and the derived document

- **What a person gets:** with an In–Out range set, File ▸ New Project from Range… opens a new
  untitled project holding exactly that range of the timeline, its graphics and its media's caches
  carried, so it opens with waveforms, transcripts and analysis already made. VR3's vertical copy
  and FC's shorts are built on the same door.
- **Decisions (draft):**
  - **CJ-51 — The derived document.** `ProjectDocument+Derived.swift`'s
    `derived(from:handle:range:path:display:)` answers a new untitled document built from a handle:
    `keep_range` applied when a range is given, the handle unchanged when none (VR3's copy). It
    carries the graphics its clips draw plus `fonts/` and `assets/`, through the started
    `GraphicStore` (G-14), and each kept media's caches: peaks, loudness, sync, speech, device
    transcripts, `cache/analysis/` whole (the mask packs included, CO-4), a cloud
    transcript with its marker only when its file records `remote_deleted: true` (one still owed a
    DELETE stays in the source, so R6-11 and R6-3 hold, N4), and `cache/reversed/<media
    id>-<digest>.mov` for each kept reversed clip (the digest is over the same media file, so it
    stays valid, and nothing renders a reverse for a windowless document, N5). It never copies media
    files (a derived project points at the source's media; a consolidated source's shorts point into
    its package) nor ramp, isolated or voiced renders (the export waits for and makes them). Copies
    are APFS clones where the volume allows (`clonefile`, `COPYFILE_CLONE`), else copies. With
    `path`, the package is written first so `cache/` lands once; the order is caches through
    `CacheLedger.publish`, then `makeWindowControllers()` (so `startCaches()` finds them current and
    starts no pass), then graphics through the started store (N6). `display: false` makes the window
    controllers (so caches and the graphic store start) and shows no window (N7). (SW-44 later adds
    every per-source cache key.)
  - **CJ-52 — File ▸ New Project from Range… and `new_project_from_range {from, to, path?}`.** The
    menu item needs an In–Out range on the top-level timeline (off inside a nest). The new document
    opens with the range as its first state, with no undo step, named "<source name> (range)" until
    saved; the source document never changes. The tool mirrors it off main, opens the document
    (saved at `path` when given, as `new_project` does) and answers its project and path; it is
    ask-first for the assistant when it names `path` (an AI-7 row: a package written where the model
    chose).
- **Core:** none (CJ5a).
- **Swift:** new `ProjectDocument+Derived.swift` (CJ-51; `ProjectDocument.swift` takes nothing, the
  reverse properties being widened by T7), new `EditorViewController+NewFromRange.swift` (the
  command and its validator arm), the File item in `AppDelegate+Menus.swift`; `UIMenuTable.swift`
  and `inventory.json`; the tool's `creatorHandlers` row and off-main name, its body in a new
  `AgentServer+Derived.swift` and its entry in a new `AgentCatalog+Derived.swift`;
  `AssistantToolTable.swift` (the ask-first row).
- **MCP mirror:** `new_project_from_range`, naming File ▸ New Project from Range….
- **Docs:** `docs/guide/projects-and-media.md` (New Project from Range, what is carried, what is
  not); `menus-and-shortcuts.md`; `mcp.md`; spec §7.9e, §9, §7.9b (AI-7's row), §5.6 (what a derived
  package holds); `app/CLAUDE.md`; root `CLAUDE.md`'s product count.
- **Acceptance:** the new project's export equals the source's export of the range; its caches are
  carried and no pass starts on open; `make gate`.
- **Proof** (`derived_proof.py`, Release): D1 a range of a fixture with a transition, a ramp, a
  timed caption page, a linked pair and a graphic across its edges opens with every track passing
  the overlap rule (read back) and the edges where asked; D2 the new project's export against the
  source's export of the range, decoded: frames byte-identical and PCM equal sample for sample away
  from the edges (the fixture keeps ducks, levellers and transitions away from them); D3 the carried
  cache files are byte-identical to the source's and no cache pass starts on open (the lane's
  count); D4 a cloud transcript with `remote_deleted: false` stays in the source and is absent from
  the copy, one with `true` is carried; D5 a kept reversed clip's backwards file is carried and its
  `render_frame` equals the source's at the same moment; D6 the graphics the kept clips draw are
  carried and no other; D7 `display: false` opens no window and the document is listed; D8 with
  `path`, `cache/` is written once (the temporary folder holds none); D9 the bytes and seconds of
  one carry on a two-camera two-microphone fixture (and on S-PC1 when present) are recorded; D10 the
  source project's JSON is byte-identical before and after; D11 the tool with `path` waits on an
  ask-first question (`assistant_answer`).
- **Mutants** (6): a transcript owed a DELETE carried (D4); the reversed file not carried (D5);
  window controllers made before the caches land (D3: a pass starts); every graphic carried (D6);
  the package written after the caches (D8); the source edited (D10).
- **Manual checks:** none. **Depends on:** CJ5a, CJ0c (T5, T7, T8). **Lane** A.
- **Question for the owner:** the new document opens with the range as its first state (no undo back
  to the whole source)? *Recommended: yes* — undo into the source's whole timeline would be a second
  copy of the source, not a range.

#### CJ5b's record (2026-11-02)

**Landed.** File ▸ New Project from Range…, the derived document and `new_project_from_range`
(spec §11 CJ-51, CJ-52, recorded and committed before the code, with AI-7's amendment) on lane
A's branch, base `f82c5b20`. No core, FFI, header or format change; `RC_FORMAT_VERSION` is
unchanged. Owner, 2026-11-01: the new document opens with the range as its first state — yes.
Every count below is a `wc -l` or a run's own output.

- **Swift:** `ProjectDocument+Derived.swift` (new, 144 lines): the door
  `derived(from:handle:range:path:display:name:)` — `keep_range` applied purely to the handle
  (`ReelProject.applying`; a refusal thrown in the core's sentence), `project.json` written
  atomically into `path` or a `<UUID>-derived` staging folder, the document made from the
  package and added, or opened untitled, read, named and counted dirty; the caches copied inside
  `saveBegan(cacheDir:)` … `saveEnded` on the SOURCE's cache folder; then
  `makeWindowControllers()`, the graphics through the started store, `showWindows()` when
  `display` and the recent item with `path`; a throw after the document exists closes it and
  removes the package it wrote. `DerivedCarry.swift` (new, 193 lines): `cachePaths` (CJ-51 (b)'s
  list per kept media id, the cloud transcript only with `remote_deleted: true`, the reversed
  render through `ReverseCache.existing`), `copy` (`copyfile` with `COPYFILE_CLONE`, a `Report`
  of files, bytes and seconds), `drawnGraphicNames`, `carryGraphics` (modules by
  `write(name:bytes:)`, fonts and assets by `importFile`, one `rescan()`).
  `EditorViewController+NewFromRange.swift` (new, 42 lines): the command and
  `validateNewFromRangeAction`; `EditorViewController.swift` one validator line; the File item
  under Pause Recording in `AppDelegate+Menus.swift` (475 → 480); `UIMenuTable.swift`'s `.window`
  row. `AgentServer+Derived.swift` (new, 77 lines) the off-main handler and the dev-only
  `-RCDevDerivedHidden`; `AgentCatalog+Derived.swift` (new, 55 lines) its row;
  `AgentServer+CreatorJobs.swift` the handler row, the off-main name and `derivedTools()`.
  `AssistantToolTable.swift` (148 → 166): `AssistantToolRow.askOnlyWith` (declared last, default
  nil), the ask-first row, `question(…)`'s nil for a call without `path` and the tool's case;
  `AssistantPrompt.swift` (177 → 178): `askFirstParagraph` spells the row "`new_project_from_range`
  with `path`", and the tool joins `searchTopics`' first topic (its words unchanged).
- **Proofs:** `tools/proof/derived_proof.py` (new): D1–D11, Z1 and the six mutants;
  `assistant_prompt_probe.swift`'s F5 pins the conditional spelling; `op_argument_proof.py`'s
  `PRODUCT_TOOLS` 109 → 110; `new_project_from_range` in `APP_STATE_TOOLS` of `phase9_proof.py`,
  `recording_proof.py` and `recording_probe.py`; `inventory.json`'s row after
  `pauseOrResumeRecording:`.
- **Documents:** spec §5.6 (what a derived package holds; 303 → 322), §7.4 (the five files' row;
  88 → 89), §7.9b (AI-7's conditional row; 161 → 165), §7.9e (the tool; 513 → 524), §9 (the File
  item; 241 → 243), the spec README's cells and the `11-decisions/` total (18385 → 18466), the
  decisions index's CJ-51 and CJ-52 rows, AI-7's row, and the `creator-jobs-4.md` (121 → 199) and
  `assistant.md` (233 → 234) rows; `docs/guide/projects-and-media.md` (### New Project from
  Range), `menus-and-shortcuts.md` (the File row), `mcp.md` (the tool row), `assistant.md` (the
  sixth ask-first tool); `tools/proof/README.md`'s CJ5b section.
- **Checks in the loop:** `make typecheck` exit 0, no error, the four baseline warnings (twice);
  `inventory.py --check` 5/5; `v2_menu.py --only H` 5 pass, 0 fail; `assistant_prompt_proof.py
  --probe` 14/14 (F5 names "new_project_from_range with path"; F6 system 3257/6000, guide
  1498/1500); `spec_index_proof.py` 240/240; `make app-debug` BUILD SUCCEEDED (the Debug parity
  trap did not fire); `recording_probe.py --only catalog` 31/31; `derived_proof.py --only
  D1,D3,D4` on Debug 4/4 (after two fixture fixes: a caption of five words with four timings, and
  `detach_audio`'s twin landing on the caption track); the whole proof on Debug 11/12, D6 failing
  on the store's own `API.md` and `API.d.ts`, which the row now sets aside; then D6 2/2.
- **`make gate`** once, on the tree committed as `e9623c8e` (before this record): PASS 447 s — names 1 s,
  typecheck 7 s (the four baseline warnings), fmt and lint skipped (no Rust input changed), test
  281 s (206 result lines, 2058 passed, 0 failed), app 157 s (D25 and D26 ok).
- **Against Release** (after the gate's `make app`): `derived_proof.py` 12/12 — D1 7 clips on 6
  tracks, end 2400000; D2 90 frames' md5s equal, 144000 samples equal away from 0.1 s at each end;
  D3 58 files carried (the answer said 58), 0 differ, eight kinds, the listing unchanged 15 s
  later; D4, D5 (`render_frame` 69453 bytes equal), D6, D8 (0 entries the call created under
  `$TMPDIR/FrameJob`), D10, D7, D11 ok; D9 40 files, 458492 bytes, 11.0 ms and 11.4 ms over two
  calls; S-PC1 skipped by name (not in `tools/proof/media/creator/`), owed. D7's check was then
  tightened from "no visible window listed" to "no window listed" (the run had listed none of 2)
  and re-run alone: 2/2. On one instance from `proof_app.py launch --app release`, stopped by its
  pid: `op_argument_proof.py` 186/186 (110 product tools; the gate refuses two strangers to
  `new_project_from_range`), `op_catalog_proof.py` 23/23, and `grep "Frame Job: "` on its log
  printed nothing.
- **Mutants** (six, on Release, each a tree copy built by `tree_copy.py`): all six CAUGHT, each exiting 1, each copy built in 159–191 s — `deleted-transcript-carried` (D4: `A`'s transcript and its marker in the copy), `reverse-not-carried` (D5: the reversed file absent and `render_frame` unequal), `windows-before-caches` (D3: the call failed, "cache/thumbs/4/0.jpg could not be carried: File exists" — the started pass had written it first), `every-module-carried` (D6: `unused.js` in the copy), `caches-in-temp-then-saved` (D8: 79 entries the call created under `$TMPDIR/FrameJob`, the reversed file among them), `source-edited` (D10: the source's project changed, its undo top "Detach Audio" → "Keep Range").

**Deviations.** The guide's `assistant.md` (the ask-first list and its question table) is edited
too: it is the page of a user-visible change the spec's guide list left out. D6 sets the store's
own manual (`API.md`, `API.d.ts`, written into every `graphics/` by `GraphicStore+Manual.swift`)
aside rather than counting it as carried. `derived_proof.py`'s mutant exit codes follow the spec
(CAUGHT 1, SURVIVED 0, not performed 2), as `assistant_session_proof.py`'s do, not
`shot_split_proof.py`'s. The door also refuses a `path` where anything exists (the tool refuses
first, in its own sentence), so the package it removes on a throw is always one it wrote.

**Review.** One review (`f82c5b20..664be1f3`, 33 files), verdict pass, two nits, both left as
they are. The carry is compared byte for byte only through the `path` door (D3–D6); the menu's
untitled door runs the same `carryCaches`, so a D10 comparison would be coverage only. And
`question(…)` takes a JSON `"path": null` as present, so such a call asks a question naming no
path where it need not: it fails safe, never running a write unasked.

**Integration.** Cherry-picked (`581258be…664be1f3`) onto `worktree-creator-jobs` at TX3's
`f82c5b20`, the lane's own base: no conflict, nothing renumbered. The owed `CLAUDE.md` edits
were applied. Root: the argument gate's "one hundred and ten product tools",
`new_project_from_range` in the app-state tool list, and `-RCDevDerivedHidden YES` among the
dev-only launch defaults. `app/CLAUDE.md`: `+Derived` in `ProjectDocument.swift`'s entry, the
five files' entry after the analysis entry, `AssistantToolTable.swift`'s ask-first list (adding
the `export_graphic` row it lacked and the conditional row), and the tool and
`creatorTools()`'s three parts in `AgentServer+CreatorJobs.swift`'s bullet. `make gate` on the
integrated tree, before this sentence: "gate: PASS 307s" (names 1 s, typecheck 7 s, fmt and lint
skipped, test 151 s with 206 result lines, 2058 passed, 0 failed, app 147 s with D25 and D26 ok).
The Release proof is the lane's above; the integration changed no app input.

**Owed.** No manual check, and nothing to file. D9's S-PC1 half, when the owner's sample lands
in `tools/proof/media/creator/`.

### CU6 — record shortcuts, under Input Monitoring

- **What a person gets:** a **Record shortcuts** checkbox in the recorder panel (off by default).
  Ticking it and pressing Record asks for Input Monitoring once, then opens its pane. While
  recording, the menu-bar item shows a keyboard mark after the dot and its menu's first, disabled
  row reads "Recording keyboard shortcuts". A sentence under the checkbox: "Records each ⌘ or ⌃
  shortcut you press, and when you type, never what you type. Nothing is recorded while an app holds
  secure input."
- **Head:** CU-S1's key verdict is not STOP (else this phase is not built and the owner was asked).
- **Core:** `cursor_file.rs`'s `keys` array is written from now on, by CU-7's rule (auto-repeats are
  typing marks, never shortcuts); no version bump (defined in v1).
- **Swift:** new `CursorKeyFilter.swift` (pure: `entry(for: event, secure: Bool) → shortcut | typed
  | none`, the whole of CU-7); new `CursorCapture+Keys.swift` (CU-S1's key source, every event
  through the filter with `IsSecureEventInputEnabled()` read at delivery); `RecordingGrant` gains
  Input Monitoring's read, step, pane URL and sentences; `RecorderPanelController+Grants.swift` asks
  it as the third step of a press (after Screen Recording, before Camera and Microphone); the
  checkbox and `FrameJobRecordingKeys` (the thirteenth key, pinned by the harness and `screens.py`);
  `RecorderStatusItem`'s mark, menu row and fixed length computed for the marks in use.
- **MCP:** `record_screen` gains `keys` (`"off"` default, `"shortcuts"`; an enum so a later mode
  needs no rename), refused without the grant (CU-3's sentence) and by name with `voice_over` and
  `camera`.
- **Docs:** `screen-recording.md` ("Shortcuts and Input Monitoring", "Permissions", the secure-input
  limit); spec §7.9d, §9 (the status item); `app/CLAUDE.md`;
  `docs/manual-checks.md` (JOB-23, JOB-24).
- **Decisions (draft):** **CU-60** the shortcut rule and the typing mark (CU-7). **CU-61** the
  indicator (amending the voice-over bullet's status item). **CU-62** the grant's order and
  sentences.
- **Acceptance:** the probes pass; a granted recording with posted shortcuts writes them spelled; a
  secure-input stretch writes nothing.
- **Proof rows:** *ungranted (probes):* Y1 `RecordingGrant`'s Input Monitoring step table; Y2 the
  status item's titles and menu rows with and without shortcuts; Y5 `record_screen keys` without the
  grant refused with the sentence, and `recording_probe.py`'s 10f gains
  `CGRequestListenEventAccess(` among the calls that may live only in
  `RecorderPanelController+Grants.swift`; Y6 `CursorKeyFilter` over 40 synthetic events (⌘⇧4 a
  shortcut spelled `cmd+shift+4`; ⇧A, ⌥E and a bare letter typed marks with no identity; an
  auto-repeat of ⌘Z a typed mark; every event with `secure: true` none). *Granted (skipped by
  name):* Y3 posted ⌘⇧4 and typing give one shortcut and N time-only marks; Y4
  `EnableSecureEventInput()` held over a typed stretch gives zero marks there.
- **Mutants** (5): the secure-input check removed (Y6); a typed key stored with an identity (Y6 and
  the core's refusal); ⇧ alone counted as a shortcut modifier (Y6); the tool asking for the grant
  (Y5's 10f); the indicator omitted (Y2).
- **Manual checks:** **JOB-23** — the Input Monitoring prompt from the app launched by the Finder,
  the pane on the next press, and whether a relaunch was needed. **JOB-24** — a real session: real
  shortcuts recorded; a password typed into a real password field leaves no mark; one typed at a
  Terminal `sudo` prompt with Secure Keyboard Entry off leaves time-only marks and no character; the
  menu-bar mark is noticed.
- **Depends on:** CU1b; CU-S1's key verdict. **Lane** B.
- **Questions for the owner:** (1) The indicator? *Recommended: the keyboard mark plus the menu row,
  sized per recording.* (2) ⌥ with arrows, delete, return, tab or escape as a shortcut?
  *Recommended: yes.*

### CJ3 — face samples

- **What a person gets:** nothing visible; agents get `kind: "faces"` from `get_media_analysis`. VR
  frames by it and SW reads mouth opening from it.
- **Head:** CJ-S2 runs (and CJ-S3 (b) with a `faces` job); verdicts recorded in CJ-30 and CJ-32.
- **Decisions (draft):**
  - **CJ-30 — `faces`, the first machine-learning kind.** Per sample of source time, every face: its
    box, confidence, roll and yaw (`VNDetectFaceRectanglesRequest` revision 3) and, from
    `VNDetectFaceLandmarksRequest` revision 3 with `constellation = .constellation76Points` set
    (revision 3 supports 76 points but does not give them unless asked,
    `VNDetectFaceLandmarksRequest.h`; the constellation is part of the kind's version and its stamp)
    on those observations, the mouth's inner-lip gap and outer-lip width, each over the face box's
    height in display pixels, so SW-81's ratio (gap over width) and a face-height ratio are one
    division at read. Each request runs with a fresh `VNImageRequestHandler`; no stateful request.
    Rate, read size and device are CJ-S2's (first numbers: 10 a second, long side 1280). Landmarks
    stay in this kind unless CJ-S2's rule 4 moves them to a `mouths` kind, which SW8 then builds on
    the same grid.
  - **CJ-31 — No identity is stored.** Each sample's faces are stored as Vision found them, in a
    fixed order (by box centre, left to right, then top to bottom). A consumer that needs a face
    followed links them itself over the window it reads: VR in the core (VR-21), SW by taking each
    sample's largest face (SW-81). No face is named or compared across media. Values are raw;
    smoothing is a planner's.
  - **CJ-32 — The compute device is pinned and recorded in the stamp.** Every supported Mac is Apple
    silicon with a CPU, a GPU and a Neural Engine; CJ-S2's rule 1 picks one per Vision request, and
    a request is pinned to it (`setComputeDevice(_:for:)`). A proof compares against the cache,
    never a recomputation (E9's rule).
- **Swift:** `AnalysisFaces.swift` (the kind, two requests on one handler per sample, the device
  pin, Vision's lower-left boxes turned into CJ-22's frame), one row in the store's kind table.
- **MCP mirror:** `get_media_analysis` gains `faces` (its prose names the fields).
- **Docs:** `docs/guide/mcp.md`; spec §5.6, §7.9e; `app/CLAUDE.md`.
- **Acceptance:** `make gate`; the verdicts recorded first; `faces_proof.py` PASS against Release.
- **Proof** (`faces_proof.py`, on the face fixtures; real-sample rows skip by name): F1 on the
  moving still the face centre's path is within 2 % of the frame width (RMS) of the path it was made
  with, and so on a trimmed placement asked by `clip`; F2 two runs on the pinned device write
  byte-identical payloads; F3 on the portrait-rotated fixture the face is upright in the answer's
  frame and within 2 % of the upright run; F4 on the two-face fixture every sample with both in
  frame holds two faces in CJ-31's order and the sample after one leaves holds one; F5 on S-TH1 the
  mean inner-lip gap in its speech spans is at least 1.5× its mean in the pauses; F6 on the
  small-face fixture recall at CJ-S2's size is recorded beside CJ-S2's figure; F7 seconds per minute
  of source recorded (no pass rule).
- **Mutants** (5): the device unpinned (F2); orientation ignored (F3); Vision's lower-left y not
  flipped (F1); sample times in clip ticks (F1's trimmed row); a sample taking the nearest frame
  instead of the first at or after (F2 across the two readers on a converting fixture).
- **Manual checks:** none (a person judges faces through VR and SW). **Depends on:** CJ2a. **Lane**
  C.
- **Questions:** none expected; CJ-S2 decides device, rate, size and reader.

#### CJ3's record (2026-11-02)

**Landed.** Lane B, base `e18ef4b4`. The commits, in order:
- `b0917aae`: the toll, `AnalysisVision.swift` (36: the device enum, `pin` with the device a
  parameter, `name(of:)`) out of `AnalysisMasks.swift` (313 → 287), a pure move; `co1_proof.py`'s
  `device-unpinned` anchor re-pointed. It came first because the spike's probe reads each
  request's pin back through `AnalysisVision.pin`.
- `d73ff658`: the head. Spike CJ-S2 run, CJ-30…CJ-35 recorded (CJ-35 pending), the instruments.
  That commit came before the app code.
- `ebcdb2cb`: the app code, its documents and the proof; CJ-34's measure and CJ-35 recorded.
- This record.

No core, FFI or format change (CJ-20), and no tool added. An agent gets
`get_media_analysis {kind: "faces"}`; a person sees nothing.

- **New files** (`wc -l`): `AnalysisFaces.swift` 270, `AnalysisFaces+Samples.swift` 135,
  `AgentServer+AnalysisFaces.swift` 101, `AnalysisVision.swift` 36.
- **Changed:** `AnalysisStamp.swift` 206 → 234 (`faces` in every switch, `vision`,
  `grid(of:)`), `AnalysisFrames.swift` 394 → 401 (the grid's `init(samplesPerSecond:duration:)`
  only), `AnalysisLane.swift` 324 → 328 (the `.faces` arm), `AgentServer+Analysis.swift` 348 →
  350, `AgentCatalog+Analysis.swift` 112 → 133, `ProjectDocument+Analysis.swift` 73 (one line:
  `kind.grid(of:)`).
- **Not touched:** `BackgroundRender.swift` and the picture queue's pause (CJ-S3 (b) did not
  fire), and the generic callers of a kind (`AgentServer+AnalysisJob.swift`, `ShotSplit.swift`,
  `CutoutMasks.swift`, `AnalyzingSheetController.swift`, `DerivedCarry.swift`).
- **Instruments:** `face_fixtures.py` (327), `creator_spike/faces_spike.swift` (270),
  `faces_deciders.py` (214, 23 selftest rows), `faces_spike.py` (217), `lane_spike.py --kind
  faces`, `faces_probe.swift` (301) and `faces_proof.py` (520: P1–P5, F1–F7, Z1, five mutants).
- **Documents:** spec §5.6 (322 → 333), §7.4 (row 50), §7.9e (524 → 540) and their index cells,
  `creator-jobs-4.md` (278 → 380) with six index rows, `docs/guide/mcp.md`,
  `projects-and-media.md`, and `tools/proof/README.md`.

**The head.** macOS 26.5.1 (25F80), Apple M2 Max, on AC power (`pmset`: "Now drawing from 'AC
Power'"), three lanes on the machine.
- **CJ-S2** (`rule_sha256` `c41417fb…95bb2b11`, matching): `VERDICT rate=10 size=720
  landmarks=yes rectangles=neural_engine(branch 1) landmarks_device=neural_engine(branch 1)
  reader=converted compare=cross_run dropped=none realtime_1080=10.30 realtime_4k=8.88`.
  - Rule 1, 600 samples of `faces_moving.mov` at 1280. Both requests have one stage
    (`VNComputeStageMain`), and every run read back the device it was pinned to. Rectangles: CPU
    13.99, 13.90 and 13.91 s; GPU 6.69, 6.84 and 6.97 s; Neural Engine 5.19, 5.21 and 5.15 s.
    Landmarks: CPU 3.59, 5.55 and 8.85 s; GPU 5.79, 3.04 and 2.76 s; Neural Engine 1.20, 1.18
    and 1.20 s. Each device's three digests were equal, and the devices' digests differed.
  - Rule 3 on `faces_small.mov`: recall 1.0000 over 600 samples at 720, 1280, 1920 and native.
  - Rule 2 at 720: 10.29, 10.30 and 10.31× on 1080p30; 8.87, 8.88 and 8.95× on 4K30.
  - Rule 4: landmarks 1.51 s against rectangles 4.02 s (0.38×).
  - Rule 5: no log or HLG sample, so converted. Rule 6 skipped.
  - One-minute loads were 6.16…41.11 over the 24 runs of rules 1 and 2.
- **CJ-S3 (b) with faces** (`rule_sha256` `209c6f01…f0309ce830`, matching; Release, PID 92365,
  stopped after): four runs of three, described in CJ-35. The recorded one: idle 600, 600 and
  600, busy 600, 600 and 600 with the job running through each play, a 0.0 % drop: no pause.
- The results files are `tools/proof/work/creator_spike/CJ-S2/results.json` and
  `CJ-S3-faces/results.json`, each with `rule_matches: true`.

**Commands and results.**
- `make typecheck` after the toll and after the app code: exit 0, the four baseline warnings.
- `co1_proof.py --only P1,…,P10` after the toll: 10/10.
- `faces_spike.py --selftest`: 23 rows, 0 failed.
- `swift_build.py typecheck --define FRAMEJOB_DEV_TOOLS tools/proof/faces_probe.swift`: exit 0.
- `faces_proof.py --only P1,…,P5`: 3/5 at first. P2's box was symmetric about the flip (an
  instrument fault). P5 found 18 decimals in the answer's bytes: `JSONSerialization` prints a
  `Double` to 17 significant figures. Fixed (below), 5/5.
- Debug (`make app-debug`), the whole proof: 11/12. F3 failed on its first measure, the largest
  difference of any box value between the upright and rotated runs (0.0310 against 0.02). The
  centres agreed (mean differences −0.0014, −0.0001, −0.0001, 0.0); the width moved between
  the two lossy encodes. F3 now scores F1's measure, the centres' RMS against 2 % of the width:
  `--only F3` 2/2 (4.16 px against 21.6). On Debug the rotated file reads about 3 frames a second
  through `Upright`'s per-pixel loop, so F3 takes about 5 minutes there.
- `make gate`: "gate: PASS 278s" (names, typecheck, fmt, lint, test and app ran). Over this
  record, before this sentence: "gate: PASS 1s" (names alone ran).
- `spec_index_proof.py` 240/240.
- **Release** (`RC_PROOF_APP=release`, after the gate's `make app`), on the final instrument:
  - `faces_proof.py`: **12/12**, F5 skipped by name. F1 RMS 5.87 px (5.77 on the trimmed
    placement); F2 31,216 bytes twice, identical; F2b 0 of 200 samples off; F3 4.16 px; F4 84
    samples with both whole, the sample at 13.6 s holding one; F6 recall 1.0000; F7 7.06 s per
    minute of 1080p30 (10.21 on Debug).
  - `analysis_proof.py --only A1,A2,A3,A9,A10,Z1`: 6/6.
  - `co1_proof.py --only M2,M3,Z1`: 4/4 (M1 runs with M2).
- Z1 printed nothing on every launch.
- **Mutants** (five): each once, on the final instrument, CAUGHT:
  - `device-unpinned` (P4): the stamp's device `rectangles:auto;landmarks:auto`.
  - `y-not-flipped` (P2): (0.125, 0.125, 0.25, 0.5) stayed at y 0.125.
  - `nearest-frame` (P3): sample 1 took frame 2, not 3.
  - `orientation-ignored` (F3, the app built as Release in a tree copy in 158 s): every rotated
    face's roll 1.5309, the centres 776.61 px apart.
  - `source-in-clip-ticks` (F1, built in 155 s): all 300 trimmed rows off their window.
  - The copy was removed after.

**What the rows found.**
- Every sample of the 60 s moving fixture held its one face; the path's RMS was 5.87 px of 1920.
- A one-face row is 176 bytes of JSON, 221 with `clip`: a default call holds 296 s of samples
  (236 s with `clip`), so a media longer than about four minutes is read in windows (CJ-34).

**Deviations.**
- **The toll came before the head**, not after it: the spike's probe calls `AnalysisVision.pin`.
- **The answer writes each rounded value as an `NSDecimalNumber`** of its shortest spelling. The
  spec assumed `JSONSerialization` prints a rounded `Double` in short form; it printed
  `0.43219999999999997`. CJ-34 records it.
- **`faces_two.mov` slides up, not left.** The two faces overlap in x (the back face spans
  158…467 px of the 1080² cover and the front 312…677), so no slide left takes the back face out
  while the front one is whole. Sliding up, the back face leaves at 13.516 s and the front is
  whole until 14.3 s.
- **F3 scores the face centres' RMS** against 2 % of the width (F1's measure), not every box
  value within 0.02 (above).
- **CJ-S3 (b)'s faces job covers the whole ten-minute still**, not 120 s: a 120 s faces job
  landed in about 9 s, inside the 20 s play. `lane_spike.py` also now reads the LAST job row for
  a media and project, since a re-run on one instance lists the earlier run's rows first.
- **F6 passes at 98 % of CJ-S2's recall** (rule 3's floor). The spec only says to record it.
- **The app mutants were built as Release** in their tree copies, as CO1's were.

**Review.** One review (`e18ef4b4..7ce3df40`), verdict pass, every Files and Approach item
done, three nits. Two applied at integration, one left as it stands:
- `analysisAnswerCap`'s doc said it capped `cuts` and `runs`; it now names `samples` (CJ-34).
- `facesAnswer` parsed each rounded value with `NSDecimalNumber(string:)` and no locale; it now
  passes `en_US_POSIX`, so the "." of `String(Double)` is read the same on any Mac. `faces_proof.py
  --only P5` after it: 1/1, the same 176 and 221 bytes.
- Left: the landmarks results are matched to the rectangles' faces by position. Vision answers
  one landmarks observation per input face, in input order; matching by `uuid` would change the
  cache's semantics only if it ever did not, and would need the app rows run again.

**Integration (2026-11-02).** Cherry-picked (`b0917aae…7ce3df40`) onto `worktree-creator-jobs`
at CO2b's `acc4cbd7`, after CU9a and CO2b. Conflicts, each kept both sides:
- `creator-jobs-4.md` holds CU9a's CU-90, CO2b's CO-22, then CJ-30…CJ-35 (518 lines; its index
  row 518, the three summaries joined), and the decision index's rows in that order. CJ-30's
  intro line's "the product tool count stays 107" became "no tool is added" (CU9a's
  `retime_range` made it 111).
- `ProjectDocument+Analysis.swift`: CO2b's form kept (the instance method builds the need, the
  `nonisolated` static takes it); CJ3's one change moved to the instance method's grid,
  `kind.grid(of: media)`. `CutoutWants` keeps `AnalysisGrid(media:)`, which is the masks grid.
- `docs/guide/mcp.md`'s `get_media_analysis` row has CJ3's faces clause and CO2b's cutout
  sentences; `projects-and-media.md`'s `cache/` row names faces beside the masks made for Remove
  Background.
- The spec indexes' cells recomputed: §7.9e 544, the `11-decisions/` folder 18799 in 38 files.
No format, so nothing renumbered. The owed `app/CLAUDE.md` edits went in: the four files in the
analysis entry's list and the `faces` paragraph after the masks one. `make typecheck`: 0 errors,
the four baseline warnings; `spec_index_proof.py` 243/243. `make gate` on the integrated tree:
PASS 318 s (names 1, typecheck 7, fmt and lint skipped, test 155, app 155). Then
`RC_PROOF_APP=release faces_proof.py` on that Release build: 12/12, F5 skipped by name, every
figure as the lane's but F7, 6.55 s per minute.

**Owed.**
- S-TH1: CJ-S2's rule 3 recall and rule 6 face share, and F5 (the mouth gap in speech against
  pauses), with the owner's talking head.
- S-TH2…S-TH4: CJ-S2's rule 5 rows on log and HLG samples (converted until then).
- Filed after the commit (`ai-drafted`, `low-priority`): the analysis reader turns every decoded
  frame upright (`Upright`), even the frames a sampled kind does not analyse. `faces` analyses one
  frame in three at 30 fps, so on a rotated media two thirds of the copies are wasted.

None is a STOP. No manual check.

### FC3 — sound events, heard on the Mac

Bet 4 opens here. FC's phases run in lane A after TX and CJ5b. No phase bumps the format. The first
draft's FC1 and FC2 are CJ5a and CJ5b. The analysis needs no key; only Rank does (FC-70).

- **What a person gets:** nothing on screen yet. An agent reads laughter, applause and cheering per
  media through `get_media_analysis {kind: "sound_events"}`; FC4 reads it too.
- **Head:** FC-S1's verdict recorded as FC-30 (without S-EV, every group is weak and FC3 proves only
  timing and stamps, on the `speech` group's onset).
- **Decisions (draft):**
  - **FC-30 — Sound events (FC-S1's verdict):** the window, hop and threshold per group, and which
    groups are first-class (admit a window to the pool) or weak (reported and given to the model,
    never admitting a window alone).
  - **FC-31 — `sound_events` is an analysis kind on CJ2a's lane and store** (its sound queue):
    `cache/analysis/sound_events/<media id>.json` and a payload `windows.bin` in its folder — per
    window, little-endian Float32 maxima for six groups: laughter (`laughter`, `belly_laugh`,
    `chuckle_chortle`, `giggling`, `snicker`), applause (`applause`, `clapping`), cheering
    (`cheering`), crowd (`crowd`), music (`music`), speech (`speech`); window k at k × hop in media
    source ticks. Classified from the 16 kHz `speechReader` decode through `SNAudioStreamAnalyzer`,
    so an MP3's encoder delay is skipped as every cache skips it (SY-42). The kind version covers
    the group table; the parameter digest the window and hop; the stamp the OS build (the classifier
    ships with the OS) and the device. Keyed by media and read from the first audio track until
    SW4a re-keys it per audio source (SW-40), the stamp then naming the stream and channel; SW3a's
    guard (SW-35) keeps a clip on another track from reading track 0's events meanwhile.
  - **FC-32 — It runs on demand, never at import (CJ-20)**, for the played spans of each heard media
    in scope; no reading of it is ever shown as a score.
- **Swift:** new `SoundEvents.swift` (pure: the group table, the payload's format and loader,
  `events(in:for:)` mapping a media's windows onto a clip's played span through `SourceMap` and
  speed; a reversed clip gives none, as for words); new `AnalysisKind+SoundEvents.swift` (the kind's
  job: `SNAudioStreamAnalyzer` over `speechReader`'s decode of each missing range, cancel, progress,
  publication through the store).
- **MCP mirror:** `get_media_analysis`' prose gains the kind; no tool of its own.
- **Docs:** spec §5.6, §7.7 (the pass, not in the import order); `docs/guide/mcp.md`;
  `app/CLAUDE.md`.
- **Acceptance:** FC-30 recorded; probes; MCP rows against Release; `make gate`.
- **Proof** (`sound_events_probe.swift`, `sound_events_proof.py`): the `speech` group's onset on a
  `say` fixture moves by exactly 2.000 s, within one hop, when 2 s of silence is prepended; an MP3
  and a WAV of the same audio give event times within one hop; a changed file re-analyses and an
  unchanged one reads the store; a window inside the coverage is a hit and one past it runs only the
  missing span; a cancelled pass publishes nothing; mapping through ×2 and a ramp matches
  `ClipLoudness`' mapping of the same steps; the answer equals the payload's values for the window;
  on S-EV, laughter recall at FC-30's threshold holds.
- **Mutants** (4): window start at k × window instead of k × hop; the MP3 trim skipped; publication
  before the payload is complete; the group table's version left out of the kind version.
- **Manual checks:** none. **Depends on:** CJ2a; FC-S1. **Lane** A.
- **Question for the owner:** run the pass at import so the first Find Clips is instant?
  *Recommended: no* (FC-32, CJ-20): every import would pay CPU for a feature most imports never use.

### CU7 — Auto Zoom

- **What a person gets:** Clip ▸ Auto Zoom… on one or more clips whose media has cursor data, at the
  top level or inside an open nest. The sheet: Zoom (1.25–4×, default 2×), Arrive before the click
  (0.6 s), Stay after the last activity (2.5 s), Follow the cursor while zoomed (on), Zoom on typing
  (on when the file has keys), Replace existing zooms (off). One undo step, "Auto Zoom"; every zoom
  is an ordinary action.
- **Core:** **`cursor_zoom.rs`**, the planner (`plan_zooms`): visits formed from anchors (down
  clicks and typing stretches; CU-S3 decides a stretch's aim); an anchor within "Stay" of the
  previous joins its visit; a scroll burst or a longer gap ends it. Each visit is a zoom-in ending
  at its first anchor, a pan for each later anchor outside the region's inner 60 %, a pan for the
  followed cursor leaving the inner 70 % for over 0.3 s (at most one a second), and a zoom back.
  **Runs and the rest placement (CU-74):** a run is adjacent clips on one track, touching, of one
  media, playing forward, each continuing the previous one's source (the halves of a split); its
  rest placement is its first clip's base `scale`, `x`, `y`; every zoom back ends at it explicitly
  (`region: null` when the clip's base equals it, else the region whose solve gives it —
  `edit_zoom.rs` gains the inverse of (★) for a placement), so a later half that starts zoomed is
  never zoomed "back" to its own base. Visits are planned over the run; a zoom-in, pan or zoom back
  never straddles a cut (moved to end or start at it); a hold crossing a cut sets the later clip's
  base to the visit's placement (`set_video`), or, when that clip has a kept action in the hold, the
  visit closes at the cut and is counted; with Replace, each later clip of a run not at the rest
  placement and moved by no kept action is reset. **A placed clip is refused (CU-75):** rest scale
  below the media's fit in its container's canvas (`fit_scale`, by more than 0.1 %) — a CO layout's
  screen, a picture in picture — "clip C is placed smaller than the canvas; a zoom would fill the
  canvas. Nest it (Clip ▸ Nest) and run Auto Zoom inside the nest."; a screen scaled up and moved
  (cropping the dock by hand) is planned; inside an open nest the zoom fills the nest's canvas. A
  reversed clip is refused (CU-5). The region has the canvas's aspect at the chosen zoom, clamped
  inside the source; visits whose zoom back would end within 1 s of the next zoom-in merge into a
  pan; times through the source map; actions clamped inside the clip; overlap with an existing
  action drops the planned action, counted. **`cursor_bursts.rs`:** typing stretches (marks under
  1.0 s apart, at least 3), shared with CU9b. **`action_class.rs`** (CJ-8 (i)), created here:
  `is_zoom` (the twin of `ActionBands.isZoom`), with `is_layout` and `moves` for CO6. The plan is
  answered as `remove_action` ops (Replace only), `set_video` ops (later bases), then
  `add_zoom_action` ops.
- **FFI:** none new (`plan_zooms` through `rc_cursor_query`, one track per clip).
- **Swift:** new `AutoZoomSheetController.swift`; new `EditorViewController+AutoZoom.swift`
  (validator: every selected clip's media has cursor data; passes the open nest's scope); the item
  in `clipMenu()` (`AppDelegate+Menus.swift`, :251–395 at `d0661e5d`; T5 leaves the file room);
  `UIMenuTable.swift` and `inventory.json` rows; the edit through `performGroupedEdit`;
  `-RCDevAutoZoomAccept YES` (dev only) presses the sheet's Zoom with its controls as set (AU-128's
  precedent).
- **MCP:** `auto_zoom {clip | clips, zoom?, lead?, stay?, follow?, typing?, replace?, from?, to?}`,
  `scope` declared, answering the actions added, replaced and dropped and the visits closed at a cut
  (`AgentServer+AutoZoom.swift`, a `creatorHandlers` row).
- **Docs:** `screen-recording.md` ("Auto Zoom"), `motion-and-transitions.md`,
  `menus-and-shortcuts.md`, `mcp.md`, the README highlight; spec §9, §7.9d; `core/CLAUDE.md`; root
  `CLAUDE.md`'s dev launch defaults (`-RCDevAutoZoomAccept`); `docs/manual-checks.md` (JOB-25).
- **Decisions (draft):** **CU-70** the visit rules and defaults. **CU-71** the replace policy.
  **CU-72** typing's aim (CU-S3). **CU-73** the twin `is_zoom`. **CU-74** runs, the rest placement,
  and no transition across a cut. **CU-75** a placed clip refused; a nest's inside allowed.
- **Acceptance:** on a fixture with known clicks the plan equals the hand-made answer; on the
  owner's sample every click falls inside a zoomed region; the proof rows against Release; `make
  gate`.
- **Proof rows:** Z1 5 clicks in 2 visits: 2 zoom-ins, 1 pan, 2 zoom backs at the stated times (core
  test and tool); Z2 the region clamped at a source corner; Z3 a ramped clip's actions placed
  through S; Z4 Replace off keeps a hand-made zoom and the overlapping plan is dropped and counted;
  Z5 (probe) `isZoom` and `is_zoom` agree on 12 fixture ends; Z6 undo removes every action in one
  step; Z7 a clip split mid-hold, Auto Zoom with Replace on the second half: its zoom back ends at
  the first half's base (±1e-6) and its base is reset to it; Z8 a visit across a run's cut places
  the picture identically either side (≤ 1 px) and no action straddles the cut; Z9 a screen placed
  side by side (scale half the fit) refused with CU-75's sentence, the same clip nested and planned
  inside with the nest clip's placement unchanged, and a screen at 1.2× the fit moved left planned;
  Z10 a reversed clip refused; Z11 Clip ▸ Auto Zoom… by `perform_menu_item` with
  `-RCDevAutoZoomAccept YES` gives, in `get_project`, the project `auto_zoom` gives with the sheet's
  values on a copy of the same project (once at the defaults, once with Arrive and Zoom set away
  from them through the sheet's remembered keys), as one undo step.
- **Mutants** (9): the merge gap ignored (Z1); the region not clamped (Z2); clip time without S
  (Z3); Replace removing non-zoom actions (Z4); the lead applied after the click (Z1); a later
  half's zoom back written as `region: null` (Z7); a transition straddling a cut (Z8); the placement
  check removed (Z9); the sheet's Arrive control not passed to the planner (Z11, with a non-default
  value set before the accept).
- **Manual check:** **JOB-25** — Auto Zoom on the owner's real tutorial: are the zooms where a
  person would put them? (A verdict carried into CU12.)
- **Depends on:** CU5, CU2. **Lane** B.
- **Question for the owner:** Replace's default? *Recommended: off*, keeping the person's zooms; the
  sheet says how many planned zooms were dropped.

### VR1 — people and salient regions found on the Mac

Bet 3 opens here. VR-1…VR-7 were recorded at CJ0a. VR builds no lane, store, sheet, shot detector or
face pass of its own (CJ2a, CJ2b, CJ3); it adds one kind, `subjects`. Nothing in it is keyed (VR-2).

- **What a person gets:** View ▸ Show Subjects draws the face, person and salient boxes of the
  selected clip at the playhead, from what is cached. Agents get `kind: "subjects"`.
- **Head:** VR-S1 runs (with CJ-S2 rules 1–3 and 5 and CJ-S3 (b) re-run for the `subjects`
  requests); verdicts recorded.
- **Decisions (draft):**
  - **VR-10 — `subjects`, one analysis kind holding people and salient regions.** Per sample, each
    person box (`VNDetectHumanRectanglesRequest` r2, `upperBodyOnly` false) and each salient box
    (`VNGenerateAttentionBasedSaliencyImageRequest` r2) with its confidence, both from one decode,
    stored in CJ-22's store and frame (`cache/analysis/subjects/`), each box its centre and size
    normalised 0…1 in display orientation, origin top-left; the revisions in the kind's version.
  - **VR-11 — The grid, the reader and the device are CJ3's.** Samples fall on the `faces` grid (or
    every other `faces` sample, VR-S1 rule 1), frames through CJ-23's reader at `faces`' long side
    (or 1440, rule 2), on CJ-32's device. Nothing is linked in the store (CJ-31); the planner links
    (VR-21). Values are raw.
  - **VR-12 — What a VR command analyses:** for each media a clip shows, the windows the clips play
    plus 1 s each side, in order `shots`, `faces`, `subjects`. CJ-20 stands: nothing runs at import.
  - **VR-13 — View ▸ Show Subjects is a per-window view state that draws only what is cached:** the
    selected clip's boxes at the playhead, picked by the playhead's source time through `SourceMap`
    and `ReverseMirror` and placed by `ProjectSnapshot`'s (★). It never starts an analysis (an
    uncached clip shows "Not analyzed — Clip ▸ Follow Subject… analyzes it") and is never persisted,
    so a proof that turns it on moves no defaults key.
  - VR adds no dev hold of its own (CJ-8 (k)).
- **Core, FFI:** none.
- **Swift:** new `AnalysisSubjects.swift` (the kind: two requests per sample on one decode, Vision's
  lower-left boxes into CJ-22's frame; one row in the kind table); new `SubjectsOverlay.swift` (the
  boxes at the playhead); `PreviewCanvasView.swift` (frozen: a stored property and a draw call); new
  `EditorViewController+Subjects.swift` (the View item's action and validator);
  `AppDelegate+ViewMenu.swift`; `UIMenuTable.swift` and `inventory.json` (verdict `.plain`).
- **MCP mirror:** `get_media_analysis` gains `subjects`; its prose names the fields and View ▸ Show
  Subjects. Show Subjects is view state, not an edit.
- **Docs:** a new `docs/guide/vertical-and-framing.md` and its `docs/guide/README.md` row;
  `menus-and-shortcuts.md`; `mcp.md`; spec §5.6, §7.9e, §9; `app/CLAUDE.md`.
- **Acceptance:** VR-S1 recorded; the proof against Release; `make gate`.
- **Proof** (`vr1_proof.py`; real-sample rows skip by name): 1 on the moving still the person box
  contains the face centre in ≥ 95 % of samples; 2 two runs on the pinned device write
  byte-identical files; 3 on the portrait-rotated moving still boxes are in display orientation; 4
  every `subjects` sample time is a `faces` sample time; 6 the covered ranges after a VR command are
  exactly the clip windows ± 1 s; 7 a probe from `app/Sources` maps a normalised box at a source
  time to canvas pixels on a cropped, scaled, ×2 and reversed placement against (★), `SourceMap` and
  `ReverseMirror`; 8 Show Subjects on an uncached clip starts no job and moves no defaults key; 9
  with `-RCDevAnalysisHold 5` a `subjects` job lands after the hold and not before; 10 on S-TH4
  (HLG) the person box is found in ≥ 90 % of samples.
- **Mutants** (5): the grid by frame index (4); orientation not applied (3); whole-media analysis
  (6); the overlay ignoring reversal (7); Show Subjects starting a job (8).
- **Manual checks:** none. **Depends on:** CJ2b, CJ3; VR-S1. **Lane** C.
- **Question for the owner:** keep Show Subjects in the product or only as a dev tool? *Recommended:
  the product* — it shows why the framing went where it did.

### FC4 — `find_clips`: the analysis any agent can rank

- **What a person gets:** an agent — the Assistant, or Claude Code through `framejob-mcp` — asks for
  a timeline's sentences, who spoke them, where the laughs and loud moments are, and up to three
  times the asked-for number of candidate windows on sentence ends, then ranks them itself. No key;
  no model runs in Frame Job.
- **Head:** FC-S3's verdict recorded (FC-41's on-device arm, FC-62's constants, FC-45's figure).
- **Decisions (draft):**
  - **FC-40 — Find Clips' words are TX1's timeline transcript over the scope, a voice heard on two
    microphones counted once.** Where two words of different clips overlap in time, have the same
    TR-8-normalised text and start within 0.25 s, the word of the clip on the track further back is
    dropped and `notes` names the pair in TX-10's sentence. A nest's words are read (FC only reads).
    The scope is the In–Out range when set, else the whole top-level timeline. With a nest open Find
    Clips is off and `find_clips` refuses: "Find Clips works on the top-level timeline. Close the
    nest (⌘↑) first."
  - **FC-41 — A sentence ends at a word ending `.`, `?`, `!` or `…`, at a gap of 0.6 s or more, or
    at a change of speaker** (the cloud label; with none and two or more voice clips at once, the
    clip's track). FC-S3 may replace the on-device arm. The splitter is TX7's (CJ-8 (j)).
  - **FC-42 — What a sentence is read for:** the FC-30 groups overlapping it or starting within 1.5
    s after its last word; its short-term loudness maximum relative to the scope's median over
    speech, in LU, from `ClipLoudness`' 10 ms steps; its words per second; the pause before it.
  - **FC-43 — A candidate is sentence-aligned and frame-snapped:** its start the first word's start
    less 0.12 s, never before the previous word's end, snapped down; its end the last word's end
    plus 0.25 s, never past the next word's start, snapped up — or, when a first-class laughter,
    applause or cheering event starts within 1.0 s of that last word, the event's end, at most 3.0 s
    past the word. Its length within [shortest, longest], 20 s and 60 s by default.
  - **FC-44 — The pool is the Mac's hint windows, at most three times the count asked for, in time
    order**, chosen greedily by a fixed sum of the readings (its weights written here before the
    code), no two overlapping by more than half the shorter. The sum is never answered or shown.
  - **FC-45 — `find_clips {from?, to?, count?, shortest?, longest?, language?, sentences?}` answers
    the analysis and runs no model:** the sentences (index, start, end, speaker, text, readings),
    the pool and `notes`; with `sentences: false` the pool alone; past 2,000 words the sentences
    page at a sentence boundary with `truncated` and `next_from`, the pool always whole. Off main;
    the assistant's Stop reaches its fill through TX1's `CancelToken`. No AI-7 row (regenerable
    caches only); no key. Risk accepted: a first call on a long timeline holds the agent lane (AI-2)
    while the fill and the sound pass run (TX-S1's and FC-S3's figure).
  - Amendments: **TR-14** "**Amended by FC-40:** `find_clips` and Find Clips also read this cache,
    through TX1's timeline transcript; captions, fillers and `CloudEstimate` still never read it."
    **AI-16** "**Amended by FC-45:** Stop also reaches `find_clips`' on-device fill, through TX1's
    `CancelToken`."
- **Swift:** new and pure `ClipSentences.swift` (FC-40's de-duplication over TX1's words, then FC-41
  through the shared splitter), `ClipSignals.swift` (FC-42 from `MediaSpeech`, `ClipLoudness` and
  `SoundEvents` in timeline ticks), `ClipPool.swift` (FC-43, FC-44); new `FindClipsRun.swift` (the
  off-main run with progress — "Transcribing 12:40 of 58:02", "Listening for laughter…" — TX1's
  `TranscriptFill` for the scope, CJ2a's wants for `sound_events`, then the answer).
- **MCP mirror:** `find_clips` (FC-45) in new `AgentServer+FindClips.swift` and
  `AgentCatalog+Shorts.swift`, a `creatorHandlers` row and off-main name, its comment naming Clip ▸
  Find Clips…' analysis (FC7a); `AssistantPrompt.swift`'s search guide gains a row "clips: find
  moments worth posting" with `find_clips`, within the 1,500-character budget (taking words from
  other rows if needed), `assistant_prompt_proof.py`'s digest re-pinned; the paid eval does not run
  for one row.
- **Docs:** `docs/guide/mcp.md`; spec §7.9e; the TR-14 and AI-16 lines; `app/CLAUDE.md`; root
  `CLAUDE.md`'s product count.
- **Acceptance:** FC-S3 recorded; `make typecheck`; the probe; the MCP proof against Release; `make
  gate`.
- **Proof** (`find_clips_probe.swift`, pure; `find_clips_proof.py`, MCP, Release): sentences on
  synthetic word lists (punctuation, gaps at 0.59 and 0.61 s, speaker changes, the track-as-speaker
  rule, FC-S3's on-device arm); de-duplication of one voice on two clips (the back track's word
  goes, the note names the pair); FC-43's edges (pre-roll clipped at the previous word, tail at the
  next, the laugh extension at 0.9 s and 1.1 s, the 3 s cap, snapping at 30 and 29.97); pool
  overlap, size and order; over MCP on a `say` fixture every window starts and ends on a sentence
  edge within the bounds, a muted clip and a clip silenced by a solo contribute no words, a nest's
  words are read, a cloud fixture's speakers are answered; `find_clips`' words equal
  `get_timeline_transcript`'s less the de-duplicated; paging at 2,000 words with the pool whole; the
  nest refusal; a launch with no Anthropic key answers in full; the assistant's Stop ends an
  on-device run with "The transcription was cancelled." (`assistant_send` against the stand-in).
- **Mutants** (6): the gap rule ≥ instead of >; de-duplication on the front track; pre-roll into the
  previous word; the laugh window 1.5 s; the pool's sum answered; de-duplication across 0.5 s.
- **Manual checks:** none. **Depends on:** FC3, TX1, TX7, CJ0c (T8); FC-S3. **Lane** A.
- **Question for the owner:** default bounds 20–60 s and pool 3 × count? *Recommended: yes* (Shorts,
  Reels and TikTok's common lengths; the model, not the pool, decides).

### CU8 — shortcut overlays

- **What a person gets:** Clip ▸ Add Shortcut Overlays puts one Keyboard keys clip per recorded
  shortcut at its moment, on a front "Shortcuts" track, for the selected clips' span. Only shortcuts
  are placed (no typed key is recorded, CU-7). One undo step, "Add Shortcut Overlays".
- **Core:** `cursor_overlays.rs` (`plan_overlays`): shortcut times mapped to project time through
  each clip's window and source map; reversed clips refused (CU-5). **Timing (CU-80):** with n the
  chord's keycaps and the canvas rate's frames, the template's last keycap presses at frame 5n + 14
  (`pressAt`, `keyboard-keys.js:94`) and it exits over the clip's last 15 frames (:95), so D_min(n)
  = 5n + 30 frames; an overlay lasts 1.5 s and never less than D_min(n); the same chord again before
  the overlay ends extends it to 1.5 s after the last press, its label "×k" (otherwise ""); a
  different chord pressed sooner ends the earlier where the later starts, the later starting at its
  press or, when the earlier has not had D_min(n), when it has — and if that delays it more than 0.5
  s after its press it is dropped and counted ("N shortcuts came too close to show"). Props: `keys`
  (spelled), `label`, `position` and `theme`. Answered as `add_track` and `add_graphic_clip` ops
  with the module's schema.
- **FFI:** none new (`plan_overlays` through `rc_cursor_query`).
- **Swift:** new `EditorViewController+ShortcutOverlays.swift`: a `keyboard-keys` module whose text
  equals the bundled template is reused, else the template is written under `GraphicStore`'s
  free-name rule (`writeGraphicModule(from:)`); the track rule (a front track named "Shortcuts" free
  in the span, else a new one); the validator (the file has shortcuts); the item in `clipMenu()`
  (`AppDelegate+Menus.swift`, :251–395 at `d0661e5d`); `UIMenuTable.swift` and `inventory.json`
  rows. The item has no sheet (it applies the defaults or the remembered position and theme), so
  its parity is row O7.
- **Template:** `keyboard-keys.js` reads the token `plus` as `+` (a G-44 template change with its
  `graphic/tests` reference); a comment at `pressAt` names the planner's D_min.
- **MCP:** `add_shortcut_overlays {clip | clips, from?, to?, duration?, position?, theme?}`, a
  `creatorHandlers` row.
- **Docs:** `screen-recording.md` ("Shortcut overlays"), `graphics.md` (`plus`),
  `menus-and-shortcuts.md`, `mcp.md`; `core/CLAUDE.md`.
- **Decisions (draft):** **CU-80** placement, D_min, the same-chord merge and the drop. **CU-81**
  module reuse. **CU-82** the `plus` token.
- **Proof rows:** O1 4 shortcuts well apart: 4 clips at the right ticks with the right `keys`; O2 at
  30 fps ⌘⇧4 then ⌘C 0.3 s later: D_min(3) is 45 frames, ⌘C would start 1.2 s late, so dropped,
  count 1, one clip; at 60 fps two clips, the first 0.75 s; O3 ⌘Z three times 0.3 s apart at 30 fps:
  one clip from the first press to 2.1 s, label "×3"; O4 a second run reuses the module; O5
  `render_frame` at a shortcut's time shows the keycaps; O6 no overlay shorter than its D_min over
  every fixture; O7 Clip ▸ Add Shortcut Overlays by `perform_menu_item` gives, in `get_project`,
  the project `add_shortcut_overlays` gives with the item's values on a copy, as one undo step.
- **Mutants** (5): overlap allowed (O1); the module rewritten every run (O4); times without S (core
  test); D_min ignored (O2, O6); repeats not merged (O3).
- **Acceptance:** core tests; the proof rows against Release; `make gate`.
- **Depends on:** CU5; CU6 for real data. **Lane** B.
- **Question for the owner:** default position and theme? *Recommended: bottom, dark over a light
  screen.*

### VR2a — the planner, and `reframe_clip` on clips with no actions

- **What a person gets:** nothing in a menu yet. An agent frames a clip with `reframe_clip`: eased
  moves on its subject, hard cuts in the framing at shot changes, the whole picture over a blurred
  copy where there is nothing to follow.
- **Head:** VR-S2 runs over the canned and cached analyses; VR-22 and VR-23's numbers recorded.
- **Decisions (draft):**
  - **VR-20 — `reframe_clip {clip, follow, zoom?, where_empty?, replace?, from_width?, from_height?,
    backdrop?, subjects?}` frames one clip on the current canvas.** `follow` is `subject` (faces,
    then people, then salient), `face`, `person`, `salient`, `center` (fill × `zoom`, centred, no
    moves), `fit` (the whole picture for the whole clip) or `keep` (set_canvas's rescale rule,
    composed into the action ends in VR2b). `where_empty` is `fit` (default) or `center`. `zoom` 1–4
    times fill, refused outside. `from_width`/`from_height` name the canvas the clip was authored
    for (default the current). `subjects` is `{samples: [{t, faces?, people?, salient?}], shots:
    [t]}` in media source ticks, boxes `{x, y, w, h, c}` in CJ-22's frame; the core turns them into
    (★)'s Q frame through the media's displayed size, so a crop never invalidates the cache.
    **Source time to clip time is one helper:** `clip_time_of_source(clip, media, t, round)` in a
    new `core/src/clip_source_time.rs`, `speech_in_clip`'s mapping lifted out whole (reflect over
    `media.duration` when reversed, subtract `in`, then `SpeedMap::time_at` when ramped, else divide
    by the speed); `audio_duck_speech.rs` calls it, so the core has one implementation. Samples
    outside the played window are dropped.
  - **VR-21 — Choosing the subject.** Tracks are built by the planner over the window it reads
    (CJ-31: nothing stored): faces and people linked across consecutive samples by IoU ≥ 0.3 with
    gaps of at most 1 s, each track split at every `shots` cut. The primary track has the highest
    presence × median area × centrality; faces outrank people; a person track containing a face
    track (the face's centre inside the person box in ≥ 80 % of shared samples) is that face's body
    and yields; salient boxes only where no face or person is present; a rival replaces the primary
    only after scoring 25 % higher for 2 s.
  - **VR-22 — Composition.** The face centre on the window's vertical centre line, 38 % of the
    window's height from the top in a window taller than wide, else centred; with no face, the top
    of the person box 12 % from the window's top (first numbers; VR-S2 sets them).
  - **VR-23 — Moves.** The subject point median-filtered over 1 s; the window moves only when the
    point leaves a dead zone (±10 % of the window's width, ±8 % of its height); a move eases in and
    out for max(0.4 s, distance ÷ 0.5 window widths a second); no move within 0.5 s of the last
    one's end unless the subject would leave the window; a still subject makes no move (first
    numbers; VR-S2 sets them).
  - **VR-24 — Cuts, loss and two people.** A shot change is a hard cut in the framing: a one-frame
    linear action ending exactly on the cut's first frame, the new shot placed on its subject's
    median over its first second. A lost subject is held 1 s, then another track if there is one,
    else an ease over 0.8 s to `where_empty`; it returns once a subject has been seen for 0.6 s. Two
    people are framed together when both primary boxes, each widened by 15 %, fit the window at the
    zoom; otherwise the primary under VR-21's hysteresis.
  - **VR-25 — `backdrop`: the blurred copy goes on a named track.** When the framing shows the clip
    `fit` anywhere, one blurred copy built by `add_blurred_background`'s builder (made `pub(crate)`)
    goes on the `backdrop` track, or on a new back-most track the op inserts when that span is not
    free there. Without `backdrop`, VR-7's first exception applies.
  - **VR-26 — What `reframe_clip` refuses**, each in its own sentence: `follow` other than `keep` on
    a text, shape, graphic or adjustment clip; a clip with no picture; a nest clip with `subject`,
    `face`, `person` or `salient` (`center`, `fit`, `keep` allowed; `fit` with `backdrop` on a nest
    refused in `add_blurred_background`'s sentence); a matte-track clip or one a matte cuts, unless
    `keep`; a base or action rotation other than 0, or a `spin` motion slot, unless `keep`; a
    following kind with no samples in the window ("clip 12 has no subjects to follow; analyze it
    first"); samples over 100,000, more than 8 boxes of a kind in a sample, times not strictly
    increasing, a coordinate outside 0…1 or a size ≤ 0; and, until VR2b, a clip carrying any action
    unless `keep` with no action naming x, y or scale. A result equal to the clip is an identity.
  - **VR-28 — The tool fills the subjects and answers within a bound.** `reframe_clip`'s tool does
    not publish `subjects` (`filledByTheApp`); the handler asks VR-12's kinds for the clip's window
    and waits up to CJ-25's bound; past it, no edit, and `{"analyzing": {"media": [ids], "covered":
    fraction}}` with "Still analyzing the media of clip 12 (40 %); call reframe_clip again to
    apply." The want stays held by the document until the job lands, fails or the document closes.
- **Core:** new `clip_source_time.rs` (the helper; `audio_duck_speech.rs` calls it, its own tests
  unchanged); new `reframe.rs` (≤ 400: the planner answering a `FramingPath` of (clip ticks, scale,
  x, y, curve) keys from the source canvas to the target); new `reframe_cover.rs` (coverage by (★),
  VR-7's motion spans, the other `follow`s, writing the path as base and actions on an action-free
  clip); new `edit_reframe.rs` (the op, the strict `Subjects` reader written out as `ZoomRegion`'s
  is, VR-26); `edit_background.rs` (the builder `pub(crate)`); `edit.rs`; `op_rows.rs`;
  `op_table.rs` (two new kinds, `Subjects` and `Follow`); `op_schema.rs` (182; two arms); `scope.rs`
  (allowed in a scope, the nest's canvas being the view's). Tests `core/tests/reframe.rs` (a still
  subject, a pan, a cut, loss, two subjects, ×2, reverse, a ramp, a crop, a nest with `center` and
  `fit`, an arrival and a During motion, `keep`, every refusal, and track linking across a gap and
  restarting at a cut) and `core/tests/clip_source_time.rs` (against `speech_in_clip`'s old
  answers).
- **FFI:** none.
- **Swift:** `ReelOps.reframeClip`; new `AgentServer+Framing.swift` (fills `subjects`, VR-28; a
  `creatorHandlers` row; off main); `AgentCatalog+Declarations.swift` (`subjects` is
  `filledByTheApp`).
- **MCP mirror:** the op tool `reframe_clip`, printed by `opTool`.
- **Docs:** `vertical-and-framing.md` (each `follow`, for agents), `mcp.md`; spec §6c, §7.9a;
  `core/CLAUDE.md` (four modules, two kinds).
- **Acceptance:** VR-S2 recorded; core tests green; the proof against Release; `make gate`.
- **Proof** (`vr2a_proof.py`, canned analyses (CJ-26), byte-exact on any Mac): 1 with the canned
  panning face in a 1080 × 1920 project, the face's canvas position (from `get_project`'s placement
  and the canned path) is inside the window's central 60 % at ≥ 98 % of samples and inside the
  canvas at 100 %; 2 coverage: with a magenta canvas, `render_frame`'s four corners are never
  magenta at 40 sampled frames of a followed clip outside fades and motion spans; 3 a still subject
  gets no action; 4 with a canned cut `x` changes exactly between the cut's previous frame and its
  first; 5 with a canned exit, the hold lasts 1 s before a move and the `fit` span has one backdrop
  on the named track; 6 ×2, reversed and ramped clips follow, compared through `SourceMap` and
  `ReverseMirror`; 7 a SlideLeft arrival keeps its motion and row 2 holds outside its span; 8 every
  refusal is the core's sentence; 9 with `-RCDevAnalysisHold 30` on an uncached fixture the tool
  answers `analyzing` and `get_project` is unchanged, and the same call after the hold applies.
- **Mutants** (8): the coverage clamp removed (2); a dead zone of 0 (core test); the cut action
  starting at the cut (4); the loss hold 0 (5); the union rule off (core test); reversal not
  reflected in the helper (6); each backdrop on its own new track (5); the bound ignored (9).
- **Manual checks:** none here. **Depends on:** VR1; VR-S2. **Lane** C. **Questions:** none
  expected.
- **Fallback split** (if VR2a's design pass finds it more than one pipeline, recorded there before
  code): **VR2a1 — the subject-choosing planner:** `clip_source_time.rs` with `audio_duck_speech.rs`
  calling it, and `reframe.rs`'s tracks, choice, composition and moves (VR-20's helper, VR-21,
  VR-22, VR-23) as a pure function answering a `FramingPath`, tested in `core/tests/reframe.rs`
  and `clip_source_time.rs`, no op and no tool; then **VR2a2 — coverage, cuts, loss and the op:**
  `reframe_cover.rs` (VR-7), VR-24, VR-25, `edit_reframe.rs` (VR-26), the two `op_table.rs` kinds
  and their `op_schema.rs` arms, `edit_background.rs`'s builder lift, the app-filled tool (VR-28)
  and every proof row above.

### FC5 — the helper's estimate, its flags, and one helper plumbing

- **What a person gets:** nothing on screen yet: a paid request can show its cost before it is sent,
  without sending the transcript (FC7b shows it).
- **Head:** FC-S2 runs (paid, cap $3.00) and its verdicts are recorded (FC-50's constants, FC-51's
  `search`, FC-63's shape).
- **Decisions (draft):**
  - **FC-50 — The helper gains one message, `estimate`**, in `agent/src/` and offered to Rasterize
    as the same diff. `{type: "estimate", id, input_tokens, output_low, output_typical}` answers
    `{type: "estimate", id, low, typical, ceiling, window, prices}` or `{… error}`. Every figure is
    `pricing.ts`'s `price` over a synthetic `usage` per round at the session's model (so an
    `above_200k` tier applies as on a real response): `low` and `typical` are one round writing
    `input_tokens` to the cache plus `output_low` / `output_typical`; `ceiling` is the dearest the
    run can bill under FC-61 and FC-63 — three rounds, round 1 writing I and outputting M, round 2
    reading I, writing M + R and outputting M, round 3 reading I + M + R, writing M + R and
    outputting M (I `input_tokens`, M `MAX_TOKENS` since every earlier response is re-sent, R
    `RANKER_REPLY_MAX` = 2,000); `window` the model's `max_input_tokens` from the Models API, or
    null. An unpriceable model answers `unknown`, never $0 (P-2). The estimate sends nothing to the
    Messages API and no transcript text.
  - **FC-51 — `configure` gains two optional keys, each absent meaning today's behaviour:**
    `fallbacks: false` sends no `fallbacks` parameter (a classifier refusal ends the turn instead of
    retrying on another model at its price); `search: false` sends no `TOOL_SEARCH` (only if FC-S2
    finds it refused beside one non-deferred tool).
  - **FC-52 — The helper's process plumbing is one type, `HelperProcess`**, owned by
    `AssistantSession` and the ranker; `AssistantSession`'s behaviour does not change.
- **Helper (`agent/`, one diff applied to Rasterize too):** `protocol.ts` (the message and event,
  `configure`'s keys); new `estimate.ts` and `estimate.test.ts`; `main.ts` (the handler, the flags);
  a `kpgalligan/rasterize` issue with the diff.
- **Swift:** new `HelperProcess.swift` (launch with the three-variable environment,
  `F_SETNOSIGPIPE`, the line splitter, the ordered write queue, close with the 2 s terminate);
  `AssistantSession.swift` owns one.
- **FFI, MCP mirror:** none.
- **Docs:** spec §7.9b (the helper's messages and keys); root `CLAUDE.md`'s `agent/` map line (the
  byte-identical claim and its date, or that the two differ by this diff until Rasterize applies
  it); the record of the Rasterize diff and its issue; `app/CLAUDE.md`.
- **Acceptance:** `make typecheck` (tsc included); `make test` (`bun test` through
  `prices_proof.py`); `assistant_session_proof.py`, `assistant_lane_proof.py` and
  `assistant_tab_proof.py` unchanged against Release; `make gate`.
- **Proof:** `estimate.test.ts` — `low`, `typical` and `ceiling` at the bundled `claude-opus-5-5`
  row, each by hand round by round (I = 25,000, M = 32,000, R = 2,000: writes 93,000, reads 84,000,
  output 96,000 tokens, $2.40), an `above_200k` row priced per round, an unpriced model `unknown`;
  `helper_estimate_proof.py` against `anthropic_fake.py` — an estimate posts nothing to
  `/v1/messages` and no `count_tokens`, the model lookup answered and its window reported; a
  `configure` without the keys sends today's request byte for byte, with `fallbacks: false` no
  `fallbacks` key, with `search: false` no `TOOL_SEARCH`.
- **Mutants** (4): the ceiling at two rounds; earlier responses left out of rounds 2 and 3; an
  unknown model at $0; `fallbacks` sent when `configure` says false.
- **Manual checks:** none. **Depends on:** FC-S2. **Lane** A.
- **Question for the owner:** Rasterize applies the same diff through one issue? *Recommended: yes*
  (`agent/src` stays one file set; Rasterize's own features could use the estimate).

### CU9a — retime a range

- **What a person gets:** Clip ▸ Retime Range… (beside Close Gap) speeds up or slows down the In–Out
  range across every unlocked track, and everything after it moves up or back. One undo step.
- **Core:** new `edit_retime.rs`, **`retime_range {from, to, rate, keep_pitch?}`**: every clip on an
  unlocked track that `from` or `to` is strictly inside is split there by `split`'s rules; each
  media clip in `[from, to)` plays at its rate × `rate` (`set_speed`'s arm, actions keeping their
  fraction, a ramp by SR-19's factor), its start becoming from + (start − from) / rate, snapped so
  touching clips still touch; text, shape, still and graphic clips in the range have start and
  duration scaled the same way (a graphic keeps its `length`, G-9); markers inside scale; clips and
  markers at or after `to` move by the range's lost length, each moved clip's linked partner with
  it; inside a nest it applies to the nest's tracks and no markers move. **Refused**, each in its
  own sentence, nothing changed: a clip in the range that is half of a linked pair (AU-94's
  sentence, "clip {c} is linked to clip {p}: Attach Audio before changing its speed or direction");
  a media clip whose rate × `rate`, or ramp factor, would pass `set_speed`'s ×0.1–×1000 or SR-19
  (a)'s clamp, naming the clip and the rate it would need; a transition touching the range; a nest
  clip in it; a timed caption page in it (SR-27's re-time is app-side); a locked track holding a
  clip at or after `from`; a range under two frames; a `rate` past ×0.1–×1000. Its `op_rows.rs` and
  `edit.rs` rows; allowed in `refused_inside`.
- **FFI:** none.
- **Swift:** `ReelOps`' builder; new `EditorViewController+Retime.swift` (Clip ▸ Retime Range…,
  needs a range; a small sheet with Rate and Keep pitch; Apply through `SpeedAudioDrop.commit`);
  `SpeedAudioDrop.mayCross` learns `retime_range` (a trial through the core, as for
  `add_speed_ramp`, SR-24); the item in `clipMenu()` (`AppDelegate+Menus.swift`) after Close Gap;
  `UIMenuTable.swift` and `inventory.json` rows; `-RCDevRetimeAccept YES` (dev only) presses Apply
  with the sheet's values.
- **MCP:** the op tool `retime_range`, its description carrying `SpeedAudioDrop`'s agent note.
- **Docs:** `speed.md` (Retime Range), `menus-and-shortcuts.md`, `mcp.md`, spec §6b, §9;
  `core/CLAUDE.md`; `app/CLAUDE.md`'s `SpeedAudioDrop.swift` entry; root `CLAUDE.md`'s dev launch
  defaults (`-RCDevRetimeAccept`); the counts.
- **Decisions (draft):** **CU-90** `retime_range`'s semantics and refusals, AU-94 kept.
- **Acceptance:** screen, microphone and camera clips sped ×4 over 10 s stay in sync after the range
  (the same source time at the same project time, ±1 tick), and the total is 7.5 s shorter.
- **Proof rows:** R1 core tests of every refusal and of sync across three tracks; R2 an export of a
  sped range decoded: the frame at the range's end equals the source frame at `to`; R4 one undo
  step; R5 a detached pair in the range refused in AU-94's sentence; R6 a clip at ×300 sped ×4
  refused naming ×1200; R7 inside a nest the nest's tracks retimed and the document's markers
  unmoved; R8 (probe) the menu's door with a clip at ×4 sped ×4 asks through `SpeedAudioDrop` first,
  and Cancel applies nothing; R9 Clip ▸ Retime Range… by `perform_menu_item` with
  `-RCDevRetimeAccept YES`, Rate ×2 and Keep pitch off, gives in `get_project` the project
  `retime_range {rate: 2, keep_pitch: false}` gives over the same range on a copy.
- **Mutants** (6): a non-media clip not scaled (R1); markers after `to` not moved (R1); a linked
  pair accepted (R5); an out-of-range product clamped (R6); the door bypassing `SpeedAudioDrop`
  (R8); the sheet's Keep pitch not passed (R9).
- **Depends on:** CJ0b (T1). **Lane** B.

#### CU9a's record (2026-11-02)

**Landed.** Clip ▸ Retime Range… and `retime_range` (spec §11 CU-90, recorded and committed
before the code, AU-94 kept) on lane B's branch, base `e18ef4b4`. No FFI, header, format or
persisted-field change; `RC_FORMAT_VERSION` is unchanged. The road map names no owner question
for CU9a. Every count below is a `wc -l` or a run's own output.

- **Toll first, committed alone:** `edit_clip_timing.rs`'s `profile_factors` and the `impl
  Project` helpers `rescale_actions`, `scaled_span`, `scaled_profile` with their docs → new
  `edit_speed_profile.rs` (116 lines), made `pub(crate)`; `edit_clip_timing.rs` 412 → 308. The
  moved lines differ from the base only in their four widened `fn` lines (a `diff` of the moved
  ranges). Gated alone: `cargo fmt --check`, `cargo test --release` 1888 passed, 0 failed, `make
  lint` clean. This was SW7a's toll; CU9a needed the helpers first, so SW7a owes nothing here.
- **Core:** `edit_retime.rs` (new, 295 lines): `Project::retime_range`, its errors and seven
  refusals in CU-90 (b)'s order (rate ×1 an identity once the rate is in range), the cuts by
  `split_under_playhead`, the pieces found before `shift_clips`, each piece by `f`, markers, the
  exit through `finish_placement`. `edit_link.rs`'s `linked_rate_sentence`, factored out of
  `linked_rate_refusal` (335 → 339). `edit.rs` the enum row after `CloseGap`, the doc-table row
  and the dispatch arm ("fifty-five" inside a nest); `op_rows.rs` the row after `close_gap`;
  `OP_COUNT` 65 → 66; `scope.rs` the "everything else" arm; `lib.rs` both mods.
  `core/tests/retime_range.rs` (new, 18 tests). The sweeps: `scope.rs`'s `every_op` row and its
  op count 65 → 66, `edit_tests.rs`' coverage row (×2 over clip 20), `op_ticks.rs` 46 → 48 tick
  arguments, 33 → 34 ops, 51 → 53 vectors, two vectors in `op_ticks_timeline.rs`,
  `op_nullability.rs` 82 → 83 optional and 74 → 75 non-plain.
- **Swift:** `ReelOps.retimeRange`; `SpeedAudioDrop.swift` (213 → 246): `mayCross` learns
  `retime_range`, `baseline(for:on:)` (`split` at each op's `from` then `to`, on its scope, the
  project when nothing applies), `crossing(applying:to:)` diffs the baseline,
  `answerFields(_:)` (the old form now calls it), the type doc and `commit`'s doc;
  `RetimeSheetController.swift` (new, 146), `EditorViewController+Retime.swift` (new, 29), one
  validator line in `EditorViewController.swift`, the item after Close Gap in
  `AppDelegate+Menus.swift` (480 → 485), `UIMenuTable.swift`'s `.sheet` row;
  `AgentServer+Retime.swift` (new, 43) and `AgentCatalog+Retime.swift` (new, 47), joined through
  `AgentServer+CreatorJobs.swift`; `retime_range` appended to `AssistantPrompt.swift`'s "cut and
  time" topic, its words unchanged.
- **Proofs:** `tools/proof/retime_proof.py` (new) and `retime_probe.swift` (new);
  `op_argument_proof.py` `PRODUCT_TOOLS` 111, `OPS` 66; `op_catalog_proof.py` 66 ops;
  `inventory.json` the `showRetimeSheet:` row, its `presentAsSheet` site and a `reached_after`
  on `SpeedAudioDrop.swift`'s `beginSheetModal` site; `screens.py`'s `NOT_SHOWN` gains
  `RCDevRetimeAccept` and `RCDevDerivedHidden` (CJ5b's key, missing: `screens.py --only
  11c-transcript-tab` P2 failed on it, so it is fixed here).
- **Documents:** spec §6b (the `retime_range` row; the transition ops moved whole to new §6d,
  `06d-edit-operations-transitions.md`, so §6b is 455 lines), §6a (the shift list), §7.4 (the four
  files' row), §7.10 (`edit_retime.rs`, `edit_speed_profile.rs`, `edit_clip_timing.rs`'s row
  trimmed, `edit_link.rs`'s sentence), §9 (the Clip item), the spec README's 06d row, line 11 and
  Lines cells, `11-decisions/` (18551 → 18617); `docs/guide/speed.md` (## Retime a range, and
  the ×12 question's doors), `menus-and-shortcuts.md` (both Clip tables), `mcp.md` (the op row);
  `tools/proof/README.md`'s CU9a section; this record, the toll table's row and SW7a's "Tolls
  first".
- **Checks in the loop:** `cargo test --release --test retime_range` 18 passed; the sweep tests;
  `cargo test --release` 1906 passed, 0 failed; `make lint` clean; `make typecheck` exit 0, the
  four baseline warnings; `swift_build.py typecheck retime_probe.swift` exit 0;
  `inventory.py --check` 5/5; `spec_index_proof.py` 243/243; `assistant_prompt_proof.py --probe`
  14/14; `v2_menu.py --only H` 5 pass, 0 fail; `make app-debug` BUILD SUCCEEDED; `retime_proof.py`
  on Debug 12/12 rows, every row on its first run.
- **`make gate`** once, on `bf55b962`: PASS 370 s — names 1 s, typecheck 7 s, fmt 3 s, lint 7 s,
  test 200 s (207 result lines, 2076 passed, 0 failed), app 151 s. Again after the `NOT_SHOWN`
  fix and this record: PASS 76 s (names 1 s, test 74 s, the other steps skipped as unchanged).
- **Against Release** (after the gate's `make app`, one instance from `proof_app.py launch --app
  release`, stopped by its pid): `retime_proof.py` 12/12 — R1 18 passed; R2 600 frames before,
  375 after, frame 225 after equal to frame 450 before (rgb24 md5), the project 7.5 s shorter,
  `render_frame` 7.5 s after equal to 15 s before (64568 bytes); R4 undo "Retime Range" and the
  project back; R5 "clip 3 is linked to clip 5: …"; R6 "clip 3 would play at ×1200, past ×1000,
  …"; R7 three 1500000-tick pieces at 5 s, the markers unmoved; R8a, R8b, R9p; R9 (its own
  instance with `-RCDevRetimeAccept YES`) equal to the tool's answer; R10 `audio_left_out` [4]
  and the exact note; Z1 nothing on either log. `op_argument_proof.py` 187/187 (111 product
  tools, 66 ops), `op_catalog_proof.py` 23/23, and `grep "Frame Job: "` on its log printed
  nothing. Then `speed_audio_probe.py` 20/20, `recording_probe.py --only catalog` 31/31,
  `screens.py --only 11c-transcript-tab` 6/6 (after the `NOT_SHOWN` fix; 5/6 before it).
- **Mutants** (eight, each CAUGHT): in the core, as edits under `cargo test --release --test
  retime_range` — the marker-collision refusal removed (two tests failed), a non-media piece not
  scaled (one), markers after `to` not moved (three), a linked clip accepted (one), an
  out-of-range product clamped (one); in the app, `retime_proof.py --mutant` on Debug tree
  copies — `sheet-apply-edit` (R8a: no question, the project changed), `keep-pitch-dropped` (R9p
  9085 vs 9086 bytes; R9 the pieces' keep_pitch [false, true]), `no-baseline` (R8a no question;
  R10 no `audio_left_out`); each copy built in 27–29 s.

**Deviations.** A rate of exactly 1 is answered as an identity right after refusal (1), before
the other refusals: CU-90 says only that ×1 is an identity, and an identity cannot need a
refusal. R9's "the op's result on a copy" is the tool's result on the same document after one
undo (which R9 checks gives back the project), the same oracle without a second document. The
tool's `to ≤ from` is a `ToolError` after both times are snapped, as `ripple_delete_range`'s is.
§7.4 has one row for the four new files, the file map's grouping, not four. The app mutants ran
on Debug copies, not Release.

**Review.** One review (`e18ef4b4..6ab91f72`, 46 files), verdict pass, one nit, left as it is:
`edit_retime.rs`'s first cut takes `Outcome::Identity | Outcome::Refused(_)` as "no cut" and
carries on, so a refused split at `from` would be skipped silently. No split can refuse today
(`split_clips` → `finish` never does), so nothing is reachable; the reviewer's alternative, a
comment or answering a split's refusal as the retime's own, is for whoever first lets a split
refuse.

**Integration.** Cherry-picked (`335d8b97…6ab91f72`) onto `worktree-creator-jobs` at CO2a2's
`e18ef4b4`, the lane's own base: no conflict, nothing renumbered. The owed `CLAUDE.md` edits were
applied. Root: the argument gate's "one hundred and eleven product tools" and
`-RCDevRetimeAccept YES` among the dev-only launch defaults. `app/CLAUDE.md`: "sixty-five op
tools" (twice), `SpeedAudioDrop.swift`'s entry (`retime_range`, `baseline(for:on:)`,
`answerFields(_:)`, the Retime Range sheet among `commit`'s doors), the four files' entry after
the derived document's, and `retime_range` with `retimeTools()` in `AgentServer+CreatorJobs.swift`'s
bullet. `core/CLAUDE.md`: `edit_clip_timing.rs`'s entry trimmed, new `edit_speed_profile.rs` and
`edit_retime.rs` entries, `linked_rate_sentence` in `edit_link.rs`'s, `locked_track`'s fourth
caller in `edit_time.rs`'s, and "sixty-five op tools" in `op_table.rs`'s. `make gate` on the
integrated tree, before this sentence: "gate: PASS 426s" (names 1 s, typecheck 7 s, fmt 3 s,
lint 9 s, test 252 s with 207 result lines, 2076 passed, 0 failed, app 154 s). The Release proof
is the lane's above; the integration changed no app input.

**Owed.** Nothing person-only: no JOB row, no screen. Nothing to file.

### VR2b — framing composed into existing actions, and Clip ▸ Follow Subject…

- **What a person gets:** select clips, choose Clip ▸ Follow Subject…, and each picture is framed on
  its subject with eased moves on its action lane, around its zooms and volume points, as one undo
  step. A nudge is an ordinary edit of an action's end on the canvas (CI-13).
- **Decisions (draft):**
  - **VR-27 — Compose, or replace.** Compose (the default): the framing path F (scale and offset
    from the source canvas to this one) is composed into the clip's base and into the x, y and scale
    of every action end; holds over an existing action are exact (F is affine in (x, y, scale) and
    commutes with the lerp); the planner schedules its own moves in the gaps between existing
    actions, and a move that cannot fit in a gap is carried by the action it overlaps, approximated
    by that action's curve and still covering. A cut inside an existing action A splits A around the
    cut's one-frame action as `split` narrows a straddled action (`edit_split.rs`'s `state_patch`
    and `narrow_to`, made `pub(crate)`): each head ends at the full evaluated state over every key A
    names, composed with the framing; the tail keeps A's end and curve. A linear A plays unchanged,
    volume included; an eased A is re-eased on each side (counted); an action naming `speed`, or one
    a trim left running past the clip's end, is not split, the cut carried approximately (counted).
    `replace: true` removes every x, y and scale key from the clip's action ends first (an action
    left empty is removed), sets the base to the source canvas's Fit placement, then composes F.
    Follow Subject replaces; Make Vertical composes. The op answers only applied, identity or
    refused, so the counts are recomputed by the command from the two handles.
  - **VR-29 — Clip ▸ Follow Subject…** applies `reframe_clip` with `replace: true` to each selected
    clip with a picture, one undo step "Follow Subject": an `add_track` "Backgrounds" at index 0
    applied first on a pure handle (a refusal stops the command with its sentence, since the grouped
    fold runs on after a refusal), each `reframe_clip` with that track as `backdrop`, and a
    `remove_track` of it when no backdrop was needed. CJ-28's Analyzing sheet shows while VR-12's
    kinds run. The sheet: Follow (Subject, Faces, People, Salient Region, Center), Zoom (100–400 %;
    100 % when the canvas's shape differs from the picture's, 125 % when it matches), Where Empty
    (Show Whole, Center); it remembers Follow and Where Empty (`FrameJobFollow*` keys); the tool
    reads no `UserDefaults` (AU-68 (f)). `-RCDevFollowAccept YES` presses Follow (AU-128's
    precedent).
- **Core:** new `reframe_compose.rs` (≤ 400: composition into base and ends, gap scheduling, splits
  at cuts, `replace`, `keep` into ends), through `edit_action.rs`'s `pub(crate)` helpers (now in
  `edit_action_end.rs`, CO2a1's toll) and the composition `edit_zoom.rs` uses; `edit_split.rs`
  (`state_patch`, `narrow_to` `pub(crate)`); `edit_reframe.rs` (VR-26's "until VR2b" bullet
  removed). Tests `core/tests/reframe_compose.rs` (an existing zoom; a linear and an eased volume
  action straddling a cut, the linear one unchanged at every tick; a speed action never split; an
  action past the clip's end; `replace`; `keep` on ends).
- **Swift:** new `EditorViewController+FollowSubject.swift` and `FollowSubjectSheetController.swift`
  (the command, validator, the Analyzing sheet, VR-29's order through `performGroupedEdit`, the
  summary's counts); one row in `AppDelegate+Menus.swift`'s `clipMenu()`; `UIMenuTable.swift` and
  `inventory.json` (verdict `.sheet`).
- **MCP mirror:** `reframe_clip`'s prose names Clip ▸ Follow Subject… as its path (Follow Subject is
  `reframe_clip` with `replace: true` per clip and a backdrop track); no new tool.
- **Docs:** `vertical-and-framing.md` (Follow Subject, each Follow, nudging, Undo);
  `menus-and-shortcuts.md`; spec §9, §6c (`replace`); a screen for the sheet
  (`designs/screens/18-follow-subject-sheet.md`, number provisional); root `CLAUDE.md`'s dev launch
  defaults (`-RCDevFollowAccept YES`); `core/CLAUDE.md`; `docs/manual-checks.md` (JOB-31, JOB-32).
- **Acceptance:** core tests; the proof against Release; the screen captured; `make gate`.
- **Proof** (`vr2b_proof.py`, canned analyses): 1 a clip with a zoom action has composed ends equal
  to F ∘ the old ends; 2 a clip with a linear volume action straddling a framing cut exports the
  same sound, sample for sample, as before; 3 an eased action split at a cut is counted as re-eased;
  4 `replace` removes x, y and scale keys and keeps volume keys; 5 a speed action is never split and
  its carried move is counted; 6 Follow Subject through `perform_menu_item` with `-RCDevFollowAccept
  YES` is one step "Follow Subject" and one undo gives back `get_project` exactly; 7 clips with a
  `fit` span leave one "Backgrounds" track, clips with none no new track; 8 coverage corners as
  VR2a's on the composed fixture; 9 (probe) the tool's handler reads no `UserDefaults` key.
- **Mutants** (6): composition skipped for existing ends (1); the split head's end from x, y and
  scale only (2); a speed action split (5); `replace` ignored (4); the Backgrounds track kept when
  empty (7); the tool reading the sheet's key (9).
- **Manual checks:** **JOB-31** — the framing's feel on T1 (S-TH1): no fidget, no lag, moves where a
  camera operator would make them. **JOB-32** — S-PC3's two-shot treatment.
- **Depends on:** VR2a, CO2a1 (`edit_action_end.rs`). **Lane** C.
- **Questions for the owner:** (1) Default zoom: fill, the widest tall window, or a tighter 110 %?
  *Recommended: fill.* (2) Two people who don't fit: follow one, or show both whole on a blurred
  background? *Recommended: follow one.* (3) Headroom: the face at 38 % from the top on a tall
  frame, or centred? *Recommended: 38 %* (VR-S2 tunes it).

### FC6 — Claude's ranking, checked, priced and cached

- **What a person gets:** nothing on screen yet: the engine FC7b drives. Its decisions are the road
  map's statement that a model may propose moments.
- **Decisions (draft):**
  - **FC-60 — A language model may propose spans of a recording by their meaning inside a command
    the person runs and reviews; it proposes, it never edits.** Find Clips' model picks and ranks
    moments and writes their reasons; the person ticks which become shorts; every edit a short
    receives is deterministic (`keep_range`, fillers by TR-8's vocabulary, captions by time). Amends
    **W-9** ("a language model may also propose spans of a recording by their meaning — Find Clips'
    moments, their titles and reasons — inside a command the person runs and reviews; it proposes
    and never edits"), **AI-6** ("Rank in the Find Clips window is a person's request: its ranking
    session may choose spans by meaning and say why; it edits nothing") and **TR-5** ("'no pipeline
    picks words to cut by meaning' still holds for the timeline being edited; Find Clips proposes
    spans to KEEP in new projects, and only after the person ticks them").
  - **FC-61 — A ranking is a one-turn helper session with one tool of the ranker's own,
    `submit_ranking`, answered by the ranker and never through the lane;** not in the catalog, no
    app tool offered. The model is the person's Assistant model (amends **AI-11**: "Find Clips ranks
    with the same model setting"); `fallbacks: false`; no compaction, no clearing, no live-context
    block. The ranker ends the turn at the first valid submission (sends `cancel`, then answers the
    call), so a run is at most three rounds. A refusal ends the run with "Claude declined to rank
    this transcript." and its cost recorded. One helper process per ranking. Amends **AI-2** ("the
    helper also runs Find Clips' one-turn ranking session, whose one tool, `submit_ranking`, is the
    ranker's own, answered by it and never through the lane").
  - **FC-62 — The request is the scope's whole transcript, sentence by sentence, with the readings
    marked, plus the pool as hints and the rules** (the count, the bounds, titles ≤ 40 characters,
    reasons ≤ 90, both in the transcript's language). Its size is estimated on the Mac (fixed +
    per_word × words + per_sentence × sentences, FC-S3's constants plus its largest residual), since
    counting at the API would send the text. Refused before anything is sent when the estimate
    passes min(600,000, `window` − 2 × (M + R)): "This timeline's transcript is too long to rank in
    one request (about N tokens; the limit is L). Set an In–Out range around part of it."; with
    `window` null the limit is 600,000 and the sentence adds "<model>'s context window could not be
    read, so the limit is Frame Job's own." (600,000 is a spend guard: its cache write alone is
    $3.00 at the bundled row.)
  - **FC-63 — The ranker checks every submission:** each pick `[first, last]` sentence indices in
    range with first ≤ last, its length after FC-43's snapping within the bounds, no two picks
    overlapping by more than half the shorter, and a pick count of at least min(count, pool size)
    and at most count. An invalid submission is answered with each problem (at most ten) within
    `RANKER_REPLY_MAX`; a third invalid one, or a turn ending with none valid, fails the run with
    "Claude did not return a usable ranking: <the last problem>.", cancelled, its cost recorded.
  - **FC-64 — Text leaves the Mac only at the person's Rank press, with the words counted and the
    estimate shown first:** "Rank sends this timeline's transcript (N words) and the moments' sound
    and loudness readings to Anthropic, using your key." No audio is sent; the estimate sends no
    text (R6-2's rule for text).
  - **FC-65 — A ranking's cost is recorded as the assistant's is, and shown in the window:** each
    `cost` event one `spend.jsonl` line with P-5's keys; Settings' month figure counts it; the
    window shows the run's figure, "· Frame Job's estimate", and "at least" for a partial one (P-8).
    (P-7's amendment lands at FC7b.)
  - **FC-66 — The last ranking is a cache, `cache/find-clips/ranking.json`:** the scope, settings,
    model, cost, picks with titles, reasons and readings, and the SHA-256 of the project JSON it was
    made from; current only while that digest, the scope and the settings match; replaced by the
    next run; carried with the package; not an analysis kind (it is about a project, not a media).
  - **FC-67 — No virality score:** no number rating a moment is computed, stored, shown or answered.
- **Swift:** new `ClipRanker.swift` (a `HelperProcess` configured by FC-61, then `estimate`, `send`,
  `submit_ranking` checked by FC-63, `cancel` at the first valid one, close; `cost` events through
  `AssistantSpend.record`; Stop with the partial cost; progress notes as status text),
  `ClipRankingRequest.swift` (FC-62's text, its estimate and limit, `submit_ranking`'s schema),
  `FindClipsPrompt.swift` (the system text, fixed for a run), `ClipRankingCache.swift` (FC-66).
- **MCP mirror:** none of its own (the question below); FC7b's `find_clips.ranking` reads the cache.
- **Docs:** spec §7.9b (the ranking session); the W-9, AI-6, TR-5, AI-2 and AI-11 lines;
  `docs/guide/assistant.md` (Find Clips uses the same key and model).
- **Acceptance:** FC-S2 recorded; the probe and proof against the stand-in; `make gate`. No paid run
  beyond FC-S2's unless a later change is likely to break what it measured.
- **Proof** (`clip_ranker_probe.swift`, `clip_ranker_proof.py`, `anthropic_fake.py` scripted, a
  scratch spend folder): a valid first submission is cached and the fake receives nothing after it;
  an invalid submission is answered with each problem (at most ten) and the second accepted; three
  invalid fail with FC-63's sentence; a turn with no submission fails; a refusal ends with FC-61's
  sentence, one ledger line and no second request; the posted body has no `fallbacks` key; every
  `cost` event is one ledger line with P-5's keys; Stop mid-stream writes one `partial: true` line;
  the request text holds every sentence once, in order, and no audio; an over-limit transcript is
  refused with nothing posted, the limit following a small model window from the fake, and the
  refusal naming the fixed limit when the lookup fails; the cache is current against the same
  project JSON and stale after one edit; `assistant_prompt_proof.py` extends to `FindClipsPrompt`'s
  pinned digest.
- **Mutants** (7): overlapping picks accepted; the length check after snapping skipped;
  `submit_ranking` routed through the lane; the ledger line only on success; a fourth submission
  allowed; the call answered before `cancel`; the cache current across an edit.
- **Manual checks:** none (quality is FC9's trial). **Depends on:** FC4, FC5, CJ1. **Lane** A.
- **Questions for the owner:** (1) Should an outside agent be able to have Frame Job rank (a keyed,
  ask-first `rank_clips {from?, to?, count?, shortest?, longest?}`)? *Recommended: no* —
  `find_clips` answers the analysis and the agent ranks with its own model, so one ranking is never
  billed twice. (2) Rank with the Assistant's model or a cheaper fixed one? *Recommended: the
  Assistant's model*, named in the estimate. (3) Titles and reasons in the transcript's language?
  *Recommended: yes.* (4) A classifier refusal ends the run rather than retrying on another model at
  its price? *Recommended: yes.*

### CU9b — Speed Up Typing

- **What a person gets:** Clip ▸ Speed Up Typing… finds typing stretches with no speech and plays
  each at ×4 (the default), keeping 0.3 s at ×1 at each end. One undo step.
- **Core:** `cursor_typing.rs` (`plan_typing`): `cursor_bursts.rs`' stretches minus every speech
  span of the media playing under them (`media.speech`, or the speech cache Swift turns into it as
  `DuckSpeech.ops` does); a stretch never holds a shortcut nor the span of the overlay that follows
  it (its Shortcuts-track clip when there, else 1.5 s), so an overlay is never sped; reversed clips
  refused (CU-5); answered as `retime_range` ops, right to left.
- **FFI:** none new.
- **Swift:** new `SpeedUpTypingSheetController.swift` (Rate ×2–×8, default ×4; shortest stretch,
  default 3 s; Keep pitch, on; Apply through `SpeedAudioDrop.commit`); before planning,
  `set_media_speech` ops for media whose spans are not stored, in the same step, as Duck by Speech
  does; pending speech detection waits under a sheet, unavailable detection refuses with a note; the
  item in `clipMenu()` (`AppDelegate+Menus.swift`, :251–395 at `d0661e5d`); `UIMenuTable.swift` and
  `inventory.json` rows; `-RCDevSpeedUpTypingAccept YES` (dev only) presses Apply with the sheet's
  values.
- **MCP:** `speed_up_typing {clip | clips, rate?, shortest?, keep_pitch?, from?, to?}`, answering
  the ranges and the time saved; a `creatorHandlers` row; the agent note.
- **Docs:** `screen-recording.md` ("Speeding up typing"), `menus-and-shortcuts.md`, `mcp.md`; root
  `CLAUDE.md`'s dev launch defaults (`-RCDevSpeedUpTypingAccept`).
- **Decisions (draft):** **CU-91** a typing stretch without speech, a shortcut or its overlay.
  **CU-92** the defaults.
- **Proof rows:** R3 a stretch overlapping speech is cut back to the speech's edges; R9 a shortcut
  in a burst splits it and the 1.5 s after it stays ×1; R10 each sped range keeps 0.3 s at ×1 at
  both ends; R11 one undo step; R12 Clip ▸ Speed Up Typing… by `perform_menu_item` with
  `-RCDevSpeedUpTypingAccept YES` and Rate set to ×6 gives, in `get_project`, the project
  `speed_up_typing {rate: 6}` gives on a copy.
- **Mutants** (4): speech spans ignored (R3); the ×1 margins dropped (R10); a shortcut inside a
  stretch (R9); the sheet's Rate not passed to the planner (R12).
- **Acceptance:** core tests; the proof rows against Release; `make gate`.
- **Depends on:** CU9a, CU7, CU8, CU5. **Lane** B.
- **Question for the owner:** sound in a sped stretch? *Recommended: sped with Keep pitch on*, as
  the clip's other speed changes are; "Mute sped stretches" only if the trial asks.

### VR3 — File ▸ Make Vertical Version…

- **What a person gets:** the sheet (Shape, Follow, Zoom, Where Empty, Make a Copy), the Analyzing
  sheet with Stop, then the copy's window at the new shape with a summary. Undo in the copy shows
  the 16:9 project.
- **Decisions (draft):**
  - **VR-30 — Make Vertical is one grouped edit applied to a document; the menu applies it to a
    copy.** `VerticalVersion.apply(to:shape:…)` is the step FC9 calls on its own short (FC-90). File
    ▸ Make Vertical Version… makes its copy with CJ5b's derived document handed the source's handle
    unchanged (no `keep_range`, so every media stays and every cache and analysis is carried); the
    step is applied there. The source never changes and gains no undo step. "Make a copy" is a
    checkbox, ticked by default and never remembered.
  - **VR-31 — The copy opens with the step as its one undo step, "Make Vertical"** (FC-90's name),
    named "<source name> (9:16)", "(4:5)" or "(1:1)" until saved.
  - **VR-32 — Shapes and sizes:** 9:16, 4:5 and 1:1, keeping the source canvas's short side and
    even (from 1920 × 1080: 1080 × 1920, 1080 × 1350 and 1080 × 1080); a shape equal to the current
    canvas is not offered. 4:5 is a size and nothing more: every rule here and in VR4 that reads
    "taller than wide" applies to it.
  - **VR-33 — How each top-level clip is treated, in order (first match):** (1) an existing blurred
    backdrop ("Blurred Background" behind a clip with the same source, in point, start and
    duration): deleted when that clip is followed or shown `fit` here, else re-filled at the new
    fill scale, centred; (2) a plate (a shape rectangle the old canvas's size at x = y = 0, scale 1,
    named "Background" or not, gets `set_shape` to the new size; an image or still named
    "Background" at the old fill scale gets `set_video` at the new one); (3) a full-frame picture (a
    media, still or image clip whose rect at its first frame spans one whole axis of the old canvas
    within 1 px and is centred within 2 % on the other — pillarboxed 4:3 counts) is followed with
    `subject`, except a rotated, `spin`-moving or matte clip (`keep`, listed); a clip with another
    motion is followed and listed with VR-7's exception; (4) a full-frame nest clip is `center`; (5)
    a graphic the old canvas's size is VR4's (VR-42); (6) every other visual clip is `keep` (a
    camera bubble, a picture-in-picture, a title, a shape, a non-full graphic). VR5b adds class 2b
    (a CO layout role, re-laid on the new canvas rather than reframed, VR-53) and step 3b; until it
    lands a role clip takes the classes above.
  - **VR-34 — The order of the step, and where it stops:** (1) `set_canvas {width, height}` with no
    rescale; (2) `add_track` at index 0 "Backgrounds" — both applied to a pure handle first, a
    refusal of either stopping the step with its sentence and nothing made; (3) VR-33's classes 1
    and 2; (4) `reframe_clip` per class-3, 4 and 6 clip with `from_width`/`from_height` the old
    canvas and `backdrop` that track, each tried on the handle, a refused one retried as `keep` and
    listed, a refused `keep` stopping the step with nothing made; (5) `remove_track` of that track
    when no backdrop was needed (`remove_empty_tracks` would remove the person's own empty tracks);
    (6) VR4's captions and graphics. The list that passed is then applied as one grouped edit, which
    reproduces the handle (`CaptionLayout.place`'s probe precedent).
  - **VR-35 — The summary** lists clips followed, shown whole, kept, re-filled, removed and not
    followed, each with its reason ("a nest", "rotated", "on a matte track", "moves by its own
    motion: Drift"), and the counts of actions re-eased and moves carried approximately (VR-27).
  - **VR-36 — `make_vertical_version {shape, follow?, zoom?, where_empty?, captions?, copy?,
    path?}`** (`shape` one of `9:16`, `4:5`, `1:1`) mirrors the sheet, off main, never asking the
    person. With `copy` (default) it opens the copy, saved at `path` when given; with `copy: false`
    it applies the step to the addressed project. It waits for analysis up to CJ-25's bound and past
    it answers as VR-28 does, opening nothing. It is ask-first for the assistant when it names
    `path` (amends **AI-7** by one row).
  - **VR-37 — Analysis comes before the copy, in the source's cache**, so the copy holds copies of
    the source's analysis files and a later run on the source reuses them; Stop on the Analyzing
    sheet makes nothing.
  - **VR-38 — The owner's verdict on vertical versions**, recorded after JOB-35 as GR-1 was: whether
    the framing, the whole-shot treatment and the captions were what the owner would post, and
    whether re-making copies after master edits was a cost (which may withdraw CJ0a's question
    8's yes before VR7a starts).
- **Swift:** new `VerticalVersion.swift` (the step as a function of a document: VR-33, VR-34,
  VR-35), `ProjectDocument+VerticalCopy.swift` (the copy through CJ5b's derived document, its name,
  the step as its one undo step), `VerticalVersionSheetController.swift`,
  `EditorViewController+VerticalVersion.swift` (the command and validator; off inside a nest and
  while a recording runs); the File item under New Project from Range… in `AppDelegate+Menus.swift`;
  `UIMenuTable.swift` and `inventory.json`; `-RCDevVerticalAccept YES` presses Make.
- **MCP mirror:** `make_vertical_version` (VR-36) in new `AgentCatalog+Framing.swift` and
  `AgentServer+VerticalVersion.swift`, a `creatorHandlers` row, off main; the assistant's ask-first
  row (`AssistantToolTable.swift`).
- **Docs:** `vertical-and-framing.md` (what is followed, re-filled and kept; upscaling — shoot 4K
  for vertical); the README highlight; `menus-and-shortcuts.md`; spec §7.9e, §9, §7.9b (AI-7's row);
  a screen for the sheet (`18b-make-vertical-sheet.md`, provisional); root `CLAUDE.md`'s dev launch
  defaults and product count; `docs/manual-checks.md` (JOB-33).
- **Acceptance:** the proof against Release; the screen captured; `make gate`.
- **Proof** (`vr3_proof.py`; a fixture on `testsrc` with canned analyses: a face clip, a no-subject
  screen clip, a clip with a zoom and a volume action, a title, a picture-in-picture image, a nest,
  a matte pair, an existing blurred background behind a face clip, a colour plate, a clip with a
  During Drift): 1 the copy's canvas is 1080 × 1920, 1080 × 1350 for 4:5 and 1080 × 1080 for 1:1,
  and the 4:5 copy's face clip passes row 7's coverage; 2 the source's
  `project.json` is byte-identical and it has no new undo step; 3 the followed, whole, kept,
  re-filled, removed and not-followed sets are the expected ones, the plate covers the new canvas
  and the old blurred copy is gone; 4 all backdrops on one track; 5 the track count is the source's
  plus at most one; 6 one undo in the copy gives back the source's `get_project`; 7 coverage corners
  as VR2a; 8 `copy: false` applies in place as one step "Make Vertical"; 9 the copy's
  `cache/analysis/` holds the source's files byte for byte, and a second run from the source counts
  no analysis job; 10 a source at 64 tracks stops at `add_track` with the core's sentence and opens
  nothing; 11 with `-RCDevAnalysisHold 30` the tool answers `analyzing` and opens nothing.
- **Mutants** (7): the spans-an-axis test widened so a picture-in-picture is followed (3); each
  backdrop on its own track (4); the step applied to the source (2); `set_canvas` with rescale (7);
  `from_width`/`from_height` omitted (1); the blurred-copy class after the full-frame class (3); the
  step continuing after step 2's refusal (10). (4:5's size is checked by row 1 with no mutant of its
  own: it is one more row of the same size rule.)
- **Manual check:** **JOB-33** — a vertical version on a phone, including how a 1080p source's ×1.78
  looks.
- **Depends on:** VR2b, CJ5b. **Lane** C.
- **Questions for the owner:** (1) Offer 4:5 (1080 × 1350) too? *Recommended: yes* (a size, nothing
  more; VR-32 includes it, and a no removes it). (2) The copy opens with the step as one undo step,
  or as its first state? *Recommended: one undo step.*

### FC7a — Clip ▸ Find Clips…: the window and the analysis

- **What a person gets:** Clip ▸ Find Clips… opens a Find Clips window for the project, with or
  without a key. It analyses the timeline or the In–Out range with progress and Stop, then lists the
  Mac's candidate windows in time order, each with its sentences, its readings as marks (laugh,
  applause, loud), a Play button, and a numbered wash on the timeline. Rank is shown and, without a
  key, greyed with the sentence saying where to set one.
- **Decisions (draft):**
  - **FC-70 — The key rule for Find Clips.** Clip ▸ Find Clips… needs no key (the analysis runs no
    model); it is enabled while a heard clip in scope can have words and no nest is open. Rank is
    the one keyed control: while `ModelKeys.present(.anthropic)` is false it is disabled, its
    tooltip CJ-11's Anthropic sentence, and the same sentence stands as a note under it; a key added
    or removed while the window is open enables or disables it at once. No key equivalent. Ranking
    has no tool (FC-61); a chosen `rank_clips` would be an unconditional row of `ModelKeys.keyed`.
  - **FC-71 — Find Clips is a window of its own per document, not a sheet**, so the person can play,
    scrub and edit while reading the list. An edit marks a shown ranking "made before the last edit"
    and offers Rank again; its spans are not remapped. Space in the window plays and pauses its
    editor's preview through `SpaceKey.route`.
  - **FC-72 — A row's Play sets the In–Out range to its span and plays it looped** (View ▸ Loop's
    `applyLoopRange`). **The timeline's Find Clips wash is its own:** a stored property `foundClips`
    (spans and numbers) added to the frozen `TimelineView.swift` as wiring and drawn by
    `TimelineView+FoundClips.swift`; the sheets' wash keeps `candidateSpans` and draws over it, and
    neither clears the other.
  - **FC-74 — The dev tool `find_clips_window {project?, action, row?}`** (Debug and Release):
    `open`, `state`, `analyse`, `rank`, `play`, `tick`, `make`; `state` answers the scope line, the
    rows (span, number, title, reason, ticked), the estimate line, Rank's enabled state and note,
    and the cost line; `snapshot_ui`'s dump reports the wash.
- **Swift:** new `FindClipsWindowController.swift` (one per document, closed with the editor window,
  held in a static table keyed by the editor so the frozen file takes nothing; Space through
  `SpaceKey.route`), `FindClipsView.swift` (the scope line, Count 10/20/30, Shortest, Longest,
  Language; progress; the list; Rank disabled until FC7b and by FC-70; notes),
  `FindClipsRowView.swift`, `EditorViewController+FindClips.swift` (the action, its validator,
  Play), `TimelineView+FoundClips.swift`; `TimelineView.swift` (frozen: `foundClips`, wiring); the
  item after Remove Filler Words… in `clipMenu()` (`AppDelegate+Menus.swift`); `UIMenuTable.swift`
  and `inventory.json` rows (without them `perform_menu_item` refuses the item and `v2_menu.py`'s H1
  and H2 fail); the window observes `ModelKeys.didChangeNotification` (CJ-10) for Rank's state; new
  `AgentServer+FindClipsDev.swift` (dev only, in `devHandlers` and `devTools()`);
  `AgentServer+Snapshot.swift` (`snapshot_ui` learns the window and wash; its toll first if the
  wiring would pass 400).
- **MCP mirror:** `find_clips` (FC4) is the analysis's mirror; Play is `set_range` plus playback;
  the dev tool drives the window for proofs.
- **Docs:** `docs/guide/find-clips.md` (new) and its README row; the README highlight;
  `menus-and-shortcuts.md`; a screen `designs/screens/17b-find-clips-window.md` (provisional); spec
  §9, §3 (a second kind of document window), §7.4, §7.9c and V-1's dev tool list; `app/CLAUDE.md`;
  root `CLAUDE.md`'s dev tool list; `tools/proof/dev_tools.py`'s count (one more,
  `find_clips_window`); `docs/manual-checks.md` (JOB-40, JOB-41).
- **Acceptance:** `make typecheck`; the panel probe; `screens.py` captures the window light and dark
  with no layout problem; the MCP rows against Release; `make gate`.
- **Proof:** `find_clips_panel_probe.swift` (offscreen: the list from a fixed `find_clips` answer;
  Count and bounds re-run the pool without re-transcribing; the validator's three states — no words,
  inside a nest, ready — each with and without a key; Rank's state and note following a `ModelKeys`
  change while open); over MCP (`find_clips_proof.py`'s window rows): `open` then `state` lists rows
  equal to `find_clips`' pool, `play` on row 2 sets the range to its span (read back), the dump's
  wash equals the pool; a launch with an empty `-RCSecretFolder` and no `ANTHROPIC_API_KEY` opens
  the window by `perform_menu_item`, lists rows, and answers Rank disabled with CJ-11's sentence;
  with Remove Silences' sheet up and closed the Find Clips wash is still drawn;
  `space_key_probe.swift` gains the window's route.
- **Mutants** (4): the menu item gated on the key; the nest arm dropped; Play without setting the
  range; `foundClips` cleared when Remove Silences' sheet closes.
- **Manual checks:** **JOB-40** — with no key, Rank's note and tooltip read as CJ-11's sentence and
  the window reads as usable without it. **JOB-41** — Play plays the moment with its sound, looping,
  and the numbered wash is legible at the timeline's three heights.
- **Depends on:** FC4, CJ1, CJ0c (T5). **Lane** A.
- **Question for the owner:** a window rather than a sheet? *Recommended: a window* (FC-71).

### CU10 — the recorder polishes on landing

- **What a person gets:** three remembered checkboxes under Show Clicks, "When it lands": **Zoom in
  on clicks**; **Show shortcuts** (live only with Record shortcuts); **Speed up typing** (live only
  with Record shortcuts). Each runs its command on the landed screen clips as its own undo step
  after the landing (AU-68's shape), in the order Auto Zoom, Add Shortcut Overlays, Speed Up Typing
  (once the speech cache exists): zooms are planned on unsplit clips, the speed-up's splits keep
  each join invisible, and its stretches avoid the overlays.
- **Swift:** new `RecordingPolish.swift` (the follow-up: `decide` covering wait, run, drop and give
  up, readiness being the speech cache for the speed-up; "busy" is AU-68 (c)'s; the panel's 0.5 s
  default-mode timer); three `FrameJobRecording…` keys (the fourteenth to sixteenth), pinned by the
  harness and `screens.py`.
- **MCP:** `record_screen` gains `auto_zoom`, `shortcut_overlays`, `speed_up_typing` (booleans,
  default false), each refused by name with `voice_over` and `camera`, refused with `place: false`
  (AU-69 (d)'s shape: "auto_zoom: true plans on the landed screen clips, so it needs place: true."),
  and the last two refused without `keys: "shortcuts"`; the answer gains each command's answer or
  its `…_error` sentence; `land_recording` takes the three.
- **Docs:** `screen-recording.md` ("When it lands"); spec §7.9d.
- **Decisions (draft):** **CU-100** follow-ups, not part of the landing. **CU-101** their order and
  readiness. **CU-102** the keys and the tool's arguments and refusals.
- **Proof rows:** P1 `land_recording` with a fixture and all three on: three undo steps in order,
  each equal to its command run by hand in that order; P2 with speech pending the speed-up waits,
  then runs; P3 a voice-over with `auto_zoom` refused by name; P4 `auto_zoom: true` with `place:
  false` refused, and `speed_up_typing: true` without `keys` refused.
- **Mutants** (3): the wrong order (P1); one combined step (P1); a refused argument accepted (P3,
  P4).
- **Acceptance:** the proof rows against Release (P1–P4 through `land_recording`, no grant); `make
  gate`.
- **Depends on:** CU3c, CU4, CU6, CU7, CU8, CU9b. **Lane** B.
- **Question for the owner:** the defaults? *Recommended: Zoom in on clicks on, Show shortcuts on
  when Record shortcuts is on, Speed up typing off.*

### VR4 — captions re-paged and graphics re-laid

- **What a person gets:** the vertical version's word captions fit the narrow frame with every
  correction kept; subtitles and text presets take the narrow frame's measure on any portrait
  project; full-frame graphics (lower thirds, title cards, charts) lay themselves out at 9:16,
  including those inserted before this phase.
- **Toll first:** `CaptionLayout.swift` (581) gives up `// MARK: - Words into cues` (420–581) to
  `CaptionCues.swift`, a pure move gated alone.
- **Decisions (draft):**
  - **VR-40 — Word caption pages are re-paged from their own words.** A caption track's pages give
    their timed words (tokens, `text.words`, the clip's start); their style is recognised by face
    and `word_style` against `CaptionStyle`, their looks by `word_style`'s keys; the words are paged
    again by the measuring builder through `CaptionLayout.place` with `replacing`, on the new
    canvas, in the same undo step (W-7 and W-10 stand). `place(replacing:)` removes each replaced
    track with its clips first (`CaptionLayout.swift:296`), so a track holding any page whose words
    are untimed or whose style is not recognised is NOT replaced: its pages are `keep` and it is
    listed. `captions: false` leaves captions to the caller (FC9).
  - **VR-41 — Text presets measure by `min(W, H)`, and the Caption preset sits higher on a tall
    canvas; one function, three callers.** `TextPreset.size(on:)` is `sizeFraction × min(W, H)`;
    `position(on:)` is `(xFraction × W, yFraction × H)`, the Caption row using 0.25 of H on a canvas
    taller than wide; the wrap stays 80 % of W. `CaptionLayout`'s Subtitles path (:327, :363),
    `TextPane.apply` (:453, :457) and `TranscribeSheetController+Style.swift` (:213) call them. On a
    canvas at least as wide as tall `min(W, H)` is H, so landscape and square output is
    byte-identical; on a portrait canvas Subtitles from Generate Captions and Import Captions, Text
    ▸ Presets and the sheet's preview change. A cue that now measures over two lines is counted.
    Amends **W-7** ("on a canvas taller than wide, the Subtitles cue builder's size is 3.5 % of the
    short side and its line 25 % of H below centre, through `TextPreset`'s functions; landscape and
    square output is byte-identical") and spec §4.3d's text Presets row ("sizes are fractions of the
    canvas's short side, positions of its width and height (§11 VR-41)").
  - **VR-42 — A graphic the size of the old canvas becomes the size of the new one:** `set_graphic
    {width, height}` with its base x and y 0 and scale 1; placement keys in its action ends composed
    by `keep`; every other graphic `keep`. Amends **G-7** ("Make Vertical re-sizes a graphic whose
    size is the old canvas to the new canvas, as an explicit `set_graphic`; `set_canvas` still never
    re-lays out a graphic").
  - **VR-43 — A bundled template lays itself out inside any canvas:** the six that measure by
    `ctx.height / 1080` (`lower-third`, `title-card`, `callout`, `bar-chart`, `counter`,
    `kinetic-type`) change to `Math.min(ctx.width, ctx.height) / 1080` — the same number on every
    landscape canvas, so their 16:9 renders are byte-identical; `docs/graphics-api.md` recommends
    it.
  - **VR-44 — A project's own copy of an old bundled template is brought up to date in a vertical
    copy.** `GraphicTemplates+Revisions.swift` holds the SHA-256 of every revision of the six files
    the repo ever shipped; in a document the step made (the menu's copy, FC's short), a module whose
    text matches one is rewritten with the new text through `GraphicStore.write(name:source:)`, its
    old text kept as the store's revision, and listed. In place (`copy: false`) nothing is rewritten
    (a module write is not part of the step's undo); such graphics are listed. A module matching no
    digest is listed only if it measures by height.
  - **VR-45 — File ▸ Re-lay Captions for This Canvas, and `relay_captions`.** The re-paging of
    VR-40 on its own, for a project whose canvas changed by hand (`set_canvas`) or whose captions
    were laid on another canvas: every top-level caption track whose pages VR-40 recognises is
    re-paged on the current canvas as one undo step "Re-lay Captions"; a track it does not
    recognise is kept and named in an informational sheet after the edit (none when all were
    re-laid). The item sits after Export Captions… in `fileMenu()`, with no key equivalent; it is
    enabled when the project (or the open nest's view, whose canvas is the nest's) has a
    recognised caption track, and off while a recording runs. Its tool, `relay_captions {project?,
    scope?}`, applies the same step and answers the tracks re-laid and the tracks kept with their
    reasons; it needs no key.
- **Swift:** `TextPane.swift` (544: the two functions, `apply` calling them); `CaptionLayout.swift`
  (after its toll); `TranscribeSheetController+Style.swift`; new `CaptionRelayout.swift`,
  `VerticalVersion+Layers.swift` (VR-42, VR-44), `GraphicTemplates+Revisions.swift`; new
  `EditorViewController+RelayCaptions.swift` (the command, its validator arm and the sheet naming
  kept tracks); the item in `AppDelegate+Menus.swift`'s `fileMenu()` after Export Captions… (its
  room counted with T5's); `UIMenuTable.swift` and `inventory.json`.
- **Graphics:** the six templates' unit line in `graphic/tests/graphics/*.js`; a `graphic/tests/`
  bounding-box test.
- **MCP mirror:** `make_vertical_version`'s `captions`, and its answer's caption and graphic counts;
  `relay_captions` (VR-45) in `AgentCatalog+Framing.swift` and `AgentServer+VerticalVersion.swift`,
  a `creatorHandlers` row declaring `scope`, its comment naming File ▸ Re-lay Captions for This
  Canvas; root `CLAUDE.md`'s product-tool count and the CJ-8 (g) counts moved by one.
- **Docs:** `vertical-and-framing.md`; `captions.md` (re-paging; Subtitles on a portrait canvas);
  `canvas-and-layers.md` (presets by the short side); `graphics.md` and `docs/graphics-api.md`; §11
  W-7's and G-7's lines; §4.3d's note; `menus-and-shortcuts.md` (Re-lay Captions); spec §9 and
  §7.9e (`relay_captions`); `docs/manual-checks.md` (JOB-34, JOB-35).
- **Acceptance:** the proof against Release; `cd graphic && cargo test --release`; `make gate`.
- **Proof** (`vr4_proof.py`): 1 every re-paged page measures at most 86 % of 1080 (the harness's
  measure through a probe); 2 every word's timeline start equals its source page's; 3 a
  hand-corrected word survives; 4 each style keeps its face; 5 a track holding an untimed page is
  not replaced, its pages kept and listed; 6 (probe) the three sites give VR-41's size, wrap and y
  on 1080 × 1920 and byte-identical patches to today's on 1920 × 1080 and 1080 × 1080; 7
  (`graphic/tests/`) each of the six templates at 1080 × 1920, at frames 0, middle and last, has
  every text element's bounding box inside the frame inset by 24 px; 8 each at 1920 × 1080 renders
  byte-identical to before; 9 a fixture holding an old revision of `lower-third.js` gets the new
  text in its copy, listed, the source keeping the old; 10 on a landscape project with word
  captions and an untimed caption track, `set_canvas` to 1080 × 1920 then File ▸ Re-lay Captions
  for This Canvas by `perform_menu_item`: one undo step "Re-lay Captions", every page of the
  recognised track within row 1's measure, the untimed track kept and named; `relay_captions` on a
  second copy gives the same `get_project`; the item validates off on a project with no caption
  track.
- **Mutants** (8): re-paging at the old width (1); words in clip time (2); style recognition falling
  back to Subtitles (4); the graphic size test by area (VR3's fixture); one template's unit line
  left (7); `TextPane.apply` not through `size(on:)` (6); the old revision matched by name (9);
  Re-lay Captions replacing an unrecognised track (10).
- **Manual checks:** **JOB-34** — re-laid captions and graphics look intended on 9:16 and 1:1.
  **JOB-35** — the vertical trial (VR-38): vertical versions of T1 and T2 watched on a phone; the
  verdict is VR-38.
- **Depends on:** VR3. **Lane** C.
- **Questions for the owner:** (1) Also offer "Re-lay Captions for This Canvas" on its own?
  *Recommended: yes* (the same code; VR-45 designs it, and a no removes the item and the tool). (2)
  Re-page from the pages, or regenerate from the cached transcript? *Recommended: from the pages*
  (keeps corrections). (3) Update a project's old template copies in a vertical copy, or only list
  them? *Recommended: update* (VR-44).

### FC7b — Rank: the estimate, the ranked list, its cost

- **What a person gets:** under the candidates the window says what Rank sends and what it will
  probably cost — "Rank sends this timeline's transcript (9,840 words) and the moments' sound and
  loudness readings to Anthropic, using your key. About $0.20–$0.45, at most $2.40, on
  claude-opus-5-5 · Frame Job's estimate at LiteLLM prices." Rank replaces the list with Claude's
  picks, best first: number, title, in and out, length, the reason, its marks, Play and a tick box.
  The window then says what the run cost. Reopening the window on an unchanged project shows the
  last ranking at no cost.
- **Decisions (draft):** **FC-73 — `find_clips` answers `ranking` only while FC-66's cache is
  current for the call** (the project's digest, the call's scope and its settings equal the cached
  ones); otherwise `ranking: null` and a `ranking_note` naming what differs. **P-7** amended
  (FC-65): "a third figure, what the last ranking cost, is shown in the Find Clips window; the month
  figure in Settings counts every response the helper priced, the assistant's and Find Clips', and
  its note says so."
- **Swift:** new `FindClipsView+Rank.swift` (the estimate line, Rank and Stop, the ranked list, the
  cost line, the stale note); `FindClipsWindowController.swift` wiring;
  `AgentServer+FindClipsDev.swift`'s `rank` and `tick`; `AgentServer+FindClips.swift` gains
  `ranking`; `ModelKeys.keyed` gains Rank.
- **MCP mirror:** `find_clips.ranking`; ranking itself has no tool (FC6's question).
- **Docs:** `find-clips.md`; `settings.md` (the month figure counts Find Clips); `assistant.md`;
  P-7's line; spec §7.9e; `docs/manual-checks.md` (JOB-42).
- **Acceptance:** the rows against the stand-in on Release; `make gate`.
- **Proof** (`find_clips_rank_proof.py`, `RC_ASSISTANT_BASE_URL` at `anthropic_fake.py`, a scratch
  `-RCSpendFolder`, the window driven by `find_clips_window`): the estimate line equals the helper's
  `estimate` event and the fake received no Messages request before `rank`; Rank disabled until the
  estimate answers, and an estimate error disables it with the error's sentence; after `rank` the
  rows equal the fake's submission after FC-43's snapping, in its order; the cost line equals the
  sum of the run's ledger lines; `find_clips` answers `ranking` for the same scope and settings,
  null with a note for another `count`, null after one edit; closing and reopening shows the cached
  ranking with no request.
- **Mutants** (4): Rank enabled before the estimate; the pool order shown after ranking; a partial
  line counted as complete; a ranking answered for another `count`.
- **Manual check:** **JOB-42** — on a real episode, the estimate's typical band holds the run's
  cost, and the reasons read as reasons, not scores.
- **Depends on:** FC6, FC7a. **Lane** A.
- **Question for the owner:** show the "at most" ceiling as well as the typical band? *Recommended:
  both* (the ceiling is the honest worst case, P-6's habit).

### CU11 — motion blur on zooms and the cursor

- **What a person gets:** a Motion blur control in the Transform section (0–100 %, the shutter as a
  fraction of a frame; off by default). A zoom or pan on that clip, and its cursor, blur along their
  motion, the same in the preview and the export. The Auto Zoom sheet gains "Motion blur" (on),
  which sets it on the clip.
- **Head:** CU-S5's verdict (zoom blur at N, or STOP for zooms; cursor blur ships either way).
- **Core:** `video.motion_blur` (0–1, written only when above 0; format p); the recipe's `blur`, the
  sub-frame placements listed when the layer's placement differs across the shutter interval, else
  none; N is CU-S5's; the cursor's `state` answers its positions at the shutter's ends; omitted
  (drawn sharp) on a layer with a transition, a dissolve, a matte role or a shadow, stated in the
  guide; the format files and `core/tests/schema_vN.rs`.
- **Swift:** new `Compositor+MotionBlur.swift` (the layer drawn N times at 1/N weight into a pooled
  canvas-sized target, then composited once with its blend); the cursor's blur in `layerSample` (N
  sprite samples along the segment between the two ends at 1/N weight, no sprite draws); the row in
  `VideoPane+Transform`.
- **MCP:** `set_video`'s `motion_blur`; `auto_zoom`'s `motion_blur`.
- **Docs:** `motion-and-transitions.md`, `screen-recording.md`; spec §5.2a, §7.3, §7.5b; both
  `CLAUDE.md` maps; `docs/manual-checks.md` (JOB-26).
- **Decisions (draft):** **CU-110** CU-S5's verdict and N. **CU-111** what blur skips. **CU-112**
  one N in preview and export; R5-1 stands; CJ-1 lifted motion blur.
- **Proof rows:** MB1 a 2× zoom mid-ease equals the mean of N single-placement renders (±1/255 per
  channel); MB2 a still layer with blur on is byte-identical to blur off; MB3 `render_frame` against
  an export frame: identical; MB4 old projects byte-identical.
- **Mutants** (3): samples leading instead of centred (MB1); weights not 1/N (MB1); blur drawn on a
  dissolve layer (core test).
- **Manual check:** **JOB-26** — the blur reads as motion and not as smear.
- **Acceptance:** CU-S5's verdict recorded; core tests; the proof rows against Release; `make gate`.
- **Depends on:** CU3a, CU7 (`auto_zoom`'s `motion_blur` is added to CU7's tool); CU-S5. **Lane**
  B.
- **Question for the owner:** the default shutter when Auto Zoom turns it on? *Recommended: 50 %* (a
  180° shutter).

### VR5 — screen recordings follow the cursor

- **What a person gets:** a vertical version of a recording with a cursor file follows the pointer,
  with moves arriving on clicks, instead of showing the screen whole.
- **Decisions (draft):** **VR-50 — `follow: cursor`.** The subject point is the recorded cursor
  (CU2's `path` request, smoothed, in source time), mapped from the recording's pixel frame into
  CJ-22's normalised frame and to clip time by VR-20's helper; the dead zone is wider (±20 % of the
  window's width); a click outside it starts a move that arrives at the click; a typing stretch,
  when keys were recorded, holds the window. **VR-51 — A clip with a cursor file is never followed
  by faces** (a face on a screen is not the subject); Make Vertical uses `cursor` for such a clip,
  and `fit` without one. **VR-52 — CU's 16:9 auto zooms are replaced in a vertical version**
  (`replace: true` for cursor-followed clips), since the vertical window is already a zoom.
- **Core:** `follow: cursor` in `reframe.rs`; `Subjects` gains `cursor: [{t, x, y, click}]`, filled
  by the app.
- **Swift:** the handler reads the clip's window through CU's `ReelCursor` `path` and `events`
  requests; `VerticalVersion` uses `cursor` per VR-51.
- **MCP mirror:** the `follow` vocabulary in the op tool's printout; `make_vertical_version`.
- **Docs:** `vertical-and-framing.md`; spec §6c; `docs/manual-checks.md` (JOB-36).
- **Acceptance:** core tests; the proof against Release; `make gate`.
- **Proof** (`vr5_proof.py`, the synthetic cursor file over `testsrc`): 1 the cursor inside the
  window at 100 % of frames and in its central 60 % at 95 %; 2 a click outside the dead zone ends a
  move on it; 3 no face followed on a clip with a cursor file.
- **Mutants** (3): faces allowed on cursor clips; the cursor dead zone at the face value; clicks
  ignored.
- **Manual check:** **JOB-36** — S-ST2's vertical version readable on a phone.
- **Depends on:** VR3 (`VerticalVersion`, `make_vertical_version`, which this phase edits), VR2b,
  CU2, CU5. **Lane** C.
- **Questions for the owner:** (1) Replace the 16:9 auto zooms, or compose with them? *Recommended:
  replace* (VR-52). (2) Should a screen and its camera in CO's layouts be re-laid (side by side
  becoming stacked on a tall canvas) instead of the screen following the cursor full-frame?
  *Recommended: yes* — built in VR5b, once CO6 exists.

### FC8a — Make Short from a range

- **What a person gets:** File ▸ Make Short from Range… asks for a folder, a caption style (a word
  style and look, or None), whether to cut filler words, and an Export row, then makes the In–Out
  range into a saved, captioned, filler-cut horizontal short queued on the Export Queue. No key.
- **Decisions (draft):**
  - **FC-80 — Make Short is, per span, in this order:** (1) the span into a new document through
    CJ5b's door (`display: false`), saved at its final path (FC-82), caches and graphics carried;
    (2) fillers: one `ripple_delete_ranges` of `FillerDetector`'s spans, "Remove Filler Words"; (3)
    the vertical step (FC-90); (4) captions: one `transcribe` with the chosen word style and
    `replace: true`, one engine per short — the clips named are the short's heard clips whose words
    FC-40 kept; `assemblyai` with `refresh` false only when every media behind them has a current
    carried transcript serving `.captions` (no request, with or without a key), else `apple` for
    all, the note saying why; (5) reverse: every reversed clip's backwards file present, else the
    short fails with "Clip N plays reversed and its backwards file is not rendered. Render it in the
    source (Clip tab ▸ Timing ▸ Render Reverse) and make the short again." (never queued to draw a
    slate); (6) save, queue the export, close. Fillers before the vertical step so the framing
    follows the final cut; captions after it so pages measure on the final canvas.
  - **FC-81 — Make Short never sends audio anywhere:** captions from a carried cloud transcript or
    the on-device engine; fillers only where a carried transcript was asked for disfluencies (TR-7),
    else skipped with a note. R6-2 stands.
  - **FC-82 — Shorts are saved, exported and closed, under names safe on disk.** Make Short asks for
    a folder once; each short is `<source stem> — <rank or n> <title>.framejob` and `.mp4` there, a
    taken name gaining " 2", " 3"…; a title or `name` is made safe first (`/` and `:` → `-`, control
    characters and leading dots and spaces dropped, cut at a character boundary to ≤ 200 UTF-8
    bytes, empty → "Short"); exported with the chosen Export row (H.264 MP4 at the canvas size, −14
    LUFS by default) through the Export Queue and closed once queued, so thirty shorts never hold
    thirty documents.
  - **FC-83 — `make_short {from, to, folder, name?, shape?, captions?, look?, remove_fillers?,
    export?}` mirrors the sheet for one span** (`export` takes the `export` tool's keys but `path`),
    off main, never asking, answering the short's path, its `export_id` and the steps that ran or
    were skipped. Ask-first for the assistant (amends **AI-7**: "`make_short` is ask-first: it
    writes a project package and queues an export where the model chose").
  - **FC-84 — File ▸ Make Short from Range… runs the same sheet over the In–Out range, with no
    key.** Until FC9 only Keep exists, and `make_short`'s `shape` other than `keep` is refused:
    "Vertical shorts need Make Vertical Version, which this build does not have yet."
- **Swift:** new `ShortMaker.swift` (FC-80's steps through existing doors and CJ5b's door, FC-81,
  FC-82, per-step notes; each step an ordinary undo step in the short; a failed step ends that short
  and says why), `ShortNames.swift` (pure: FC-82), `MakeShortSheetController.swift`,
  `EditorViewController+Shorts.swift`; the item after New Project from Range… in
  `AppDelegate+Menus.swift`'s `fileMenu()`; `UIMenuTable.swift` and `inventory.json` rows;
  `-RCDevMakeShortAccept <folder>` (dev only: the sheet takes that folder in place of its panel and
  presses Make); `AssistantToolTable.swift` (`make_short`'s ask-first row);
  `AssistantPrompt.swift` (the search guide's clips row becomes "clips: find moments worth posting,
  make shorts" with `make_short`, and a paragraph after Cutting words: "Shorts: `find_clips` answers
  a timeline's sentences and candidate moments; choose moments only when the person asks, say which
  and why, then make each with `make_short`."; drift-checked and re-pinned).
- **MCP mirror:** `make_short` (FC-83) in new `AgentServer+Shorts.swift` and
  `AgentCatalog+Shorts.swift`, a `creatorHandlers` row and off-main name, naming File ▸ Make Short
  from Range….
- **Docs:** `find-clips.md`, `export.md`, `mcp.md`, `menus-and-shortcuts.md`; a screen
  `17c-make-short-sheet.md` (provisional); spec §7.9e, §7.9b (AI-7's row), §9; root `CLAUDE.md`'s
  product count and dev launch defaults (`-RCDevMakeShortAccept`); `docs/manual-checks.md`
  (JOB-43).
- **Acceptance:** `make typecheck`; the proof against Release; `make gate`; the paid prompt eval
  once (`assistant_prompt_eval.py --live --cap 1.00`), its dollars reported.
- **Proof** (`make_short_proof.py`, Release, `assemblyai_fake.py`): from a fixture with a carried
  disfluent cloud transcript the package exists in the folder; the filler's span is gone
  (`get_transcript` of the short has no filler, its duration the range less the cut); caption pages
  come from the carried transcript with zero requests; with an AssemblyAI key set and one uncarried
  media, captions use `apple` and the fake receives zero requests; the export is queued and
  `export_status` reaches done, the decoded movie's duration equal to the project's to a frame and
  its loudness −14 LUFS ±0.5 by the proof's BS.1770; with no cloud transcript fillers are skipped
  with the note and captions run on device; a reversed clip's `render_frame` in the short equals the
  source's, and with its backwards file removed from the source first the short fails with FC-80's
  sentence and nothing is queued; the source's JSON byte-identical; a name collision gains " 2", and
  a `name` of `"../a:b\u0007"` lands as `-a-b` inside the folder (`ShortNames` probe rows for
  leading dots, control characters and the 200-byte cut); the short's document is closed after
  queueing with no window shown; the assistant's call waits on an ask-first question; File ▸ Make
  Short from Range… by `perform_menu_item` with `-RCDevMakeShortAccept <scratch folder>` makes a
  package whose `project.json` equals `make_short`'s for the same range, folder and the sheet's
  values (the path aside).
- **Mutants** (7): captions before fillers; `assemblyai` when only some media are carried; a short
  queued with a pending reverse; the document left open; the ask-first row removed; `/` kept in a
  name; the sheet's Remove filler words box not passed (the menu row).
- **Manual check:** **JOB-43** — a short opens as an editable project, and its captions, cut and
  sound are right on a phone.
- **Depends on:** CJ5b, FC4, CJ0c (T5). **Lane** A.
- **Questions for the owner:** (1) Default Export row and loudness? *Recommended: H.264 MP4 at the
  canvas size, −14 LUFS.* (2) Also remove pauses? *Recommended: not by default; a later option.*

### CU12 — the owner's screen-tutorial trial

- **What a person gets:** a verdict. The owner records one real screen tutorial (10–20 min,
  narrated, Record shortcuts on, a camera beside) with Frame Job and cuts it with this bet's tools,
  against T2, the tutorial cut alongside TX before these tools existed (CJ-5).
- **Record (CU-120…):** the verdict as GR-1 recorded grading's; the time spent against the baseline
  cut; what was redone by hand; each item the owner wants changed, done in a fix pass or filed.
  JOB-25's zoom verdict is carried in.
- **No code, proof or mutants** unless the verdict asks for a fix (then CU13, sized after).
- **Depends on:** CU10, CU11. **Lane:** beside B (CO6 goes on).

### CJ6 — the clip ceiling

- **What a person gets:** projects with more cuts, if the measurement allows: a long talk cut word
  by word, a two-hour podcast switched every few seconds.
- **Head:** CJ-S1 runs. If its verdict keeps 4,096, the phase ends with the verdict recorded in CJ-9
  and no code.
- **Decisions (only if earned):** **CJ-60 — `MAX_CLIPS` and `RC_MAX_CLIPS` rise together to CJ-S1's
  N, with no format bump.** The file's shape is unchanged; an older build refuses a file over its
  own ceiling with "too many clips", losing nothing. Risk accepted: that build names a ceiling
  rather than "a newer Frame Job".
- **Core:** `format.rs`'s `MAX_CLIPS` and the header's define; new `core/tests/clip_ceiling.rs` (one
  past the new ceiling refused by name; at the ceiling read and written); the scope test naming
  4,096 (`core/tests/scope.rs:998`) reads the constant.
- **FFI:** the define only. **Swift:** nothing (`CaptionLayout.swift` and `CaptionImporter.swift`
  read the define). **MCP mirror:** none.
- **Docs:** spec §5.6 (where the caps are stated), §7.1; `docs/guide/` where the cap is named.
- **Acceptance:** `make gate`. **Proof:** CJ-S1's bench re-run at the new N against Release, every
  figure inside its rule.
- **Mutants** (2): the header's define left at 4,096 (`schema_v3.rs`'s header test, extended to the
  caps); the writer's cap above the reader's.
- **Manual checks:** none. **Depends on:** CJ0a. **Lane** C (just before SW2b, its only waiting
  consumer).
- **Question for the owner:** raise to the spike's N if it passes? *Recommended: yes.*

### FC8b — Make Shorts from the ranked list

- **What a person gets:** in the Find Clips window, ticking moments and pressing Make N Shorts opens
  the Make Short sheet once; a progress list follows, one line per short ("3 · The one sentence… —
  queued"), with Reveal and Open on each finished line.
- **Swift:** new `FindClipsView+Shorts.swift` (the button, the sheet, the progress list, failures);
  new `ShortBatch.swift` (runs `ShortMaker` one span at a time on main hops, documents closed
  between, Stop between shorts); `AgentServer+FindClipsDev.swift`'s `make` action with the sheet's
  choices as arguments.
- **MCP mirror:** `make_short` per span is the batch's mirror; an agent loops.
- **Docs:** `find-clips.md`.
- **Acceptance:** the rows against Release; `make gate`.
- **Proof** (`make_shorts_batch_proof.py`, Release; five spans of about 2 s, captions None, a small
  export row, so the run fits the 600 s cap): five ticked spans make five packages and five queued
  exports, named by rank; a hostile title from `anthropic_fake.py` (`"/../.x:y"`) lands as a safe
  name inside the folder; at no time are more than two documents open beyond the source; a failing
  span (its media missing) is listed and the rest go on; Stop between shorts leaves finished ones
  and makes no more; the batch's carried bytes and seconds are recorded. Behind `--long` only:
  thirty spans of 20–60 s with captions, time and disk recorded.
- **Mutants** (3): each document kept open; stopping on the first failure; naming by pool index.
- **Manual checks:** none beyond JOB-43. **Depends on:** FC7b, FC8a. **Lane** A. **Questions:**
  none.

### CO6 — layouts at the playhead

- **What a person gets:** Clip ▸ Camera Layout ▸ Corner, Rounded Corner, Circle, Side by Side,
  Stacked, Camera Full and Screen Only, plus Corner ▸ the four corners. With two video clips
  selected the front one is the camera and the one behind it the screen; with one selected it is the
  camera and the screen is the front-most clip drawing behind it at the playhead; with none, the
  camera is the clip at the playhead on the front-most track named "Camera". The switch eases over
  half a second from the playhead and holds until the next switch; at a clip's first frame it cuts.
- **Decisions (draft):**
  - **CO-60 — A layout is a placement of the camera and the screen, solved by the core.** Five:
    `corner` (shape `square`, `rounded` or `circle`; corner `bottom_right` by default; the box is
    CAM-10 (3)'s — a quarter of the canvas wide, a third tall, inset 5 % of each axis; `square` and
    `rounded` fit the camera's aspect in it, `circle` a square crop with the radius half its side,
    `rounded`'s radius 8 % of the box's shorter side); `side_by_side` (the camera in the right
    third, the screen fitted in the left two-thirds, a margin of 4 % of the canvas's shorter side
    round and between them, a 2 % radius on each); `stacked` (the screen fitted to the full width
    less the margins at the top, the camera filling the rest below, cropped to it); `camera_full`
    (the camera at `fill_scale`); `screen_only` (the camera's opacity 0). In every layout but
    `side_by_side` and `stacked` the screen takes its FULL placement — the one `add_clip` gives a
    new clip of its media: centred, `fit_scale`'s scale (honouring `canvas.fit_new_clips`, never
    scaling up), uncropped, square-cornered, opaque. A layout writes x, y, scale, crop, corner
    radius and opacity on each role, all six always, and nothing else. Every number is in
    `core/src/layout.rs`.
  - **CO-61 — A switch is a layout action, and it holds until the next one.** `switch_layout`
    writes, per role, one LAYOUT ACTION on the clip of that role under `at`, of `duration` (0.5 s,
    `ease_in_out`, at least one frame) from `at`; or, when `at` is the clip's first frame, the
    layout as the clip's base props plus a one-frame layout action at its start whose end equals
    them (a cut, recognisable by content). The REACH runs from `at` to the start of the first later
    layout action on that role's track, or to `through` when given and earlier, or to the track's
    end; every role clip STARTING inside the reach takes the layout as its base props; a clip whose
    own layout action starts after its first frame takes the new base for its head and keeps that
    action. One op, one undo step, "Camera Layout".
  - **CO-62 — A switch never fights a zoom.** Inside the reach and at or after `at`, a role clip
    holding a zoom action or another action that MOVES it (an end naming any of the six keys that is
    not a layout action) is refused by name: "The screen clip at 1:02 zooms (action 2); nest the
    screen's clips so the layout moves the nest and the zoom stays inside it." `switch_layout {nest:
    true}` nests each such role's clips in the reach first, in the same step (R5-3's precedent: a
    structural change only when a person said yes or an agent named it). An earlier layout action is
    never a reason to refuse. A nest-clip camera refuses `circle` and `rounded` (a nest clip cannot
    draw a radius, `nest.rs:382–394`); `side_by_side` and `stacked` write their 2 % radius on a nest
    clip, which draws square corners (a recorded limit).
  - **CO-63 — Actions are classed by content, with no tag** (CU-5): `action_class.rs` (CJ-8 (i), CU7
    made it): a ZOOM is an end whose `video` keys are exactly `scale`, `x`, `y` and that names no
    other group or `speed`; a LAYOUT ACTION names all six; an action MOVES its clip when its `video`
    names any of the six. A layout action is never a zoom, so Auto Zoom's Replace never removes one.
- **Core:** new `layout.rs` (CO-60's geometry, pure, through (★) and `edit_fit.rs`); new
  `edit_layout.rs` (`switch_layout {camera, screen?, layout, shape?, corner?, at, duration?, curve?,
  focus?, nest?, through?}`, composing `add_action`, `set_action_end`, `set_video` and, with `nest`,
  `nest`; CO-61's reach, CO-62's refusals); `action_class.rs` gains `is_layout` and `moves` if CU7
  left them out; the `op_rows.rs` row; `edit.rs`; `scope.rs` (allowed in a nest scope).
  `core/tests/layout.rs` (each layout's boxes on 16:9, 9:16 and 1:1; `corner`/`square` equal to
  CAM-10 (3)'s numbers exactly; the screen's full placement equal to `add_clip`'s for a smaller
  screen and with `fit_new_clips` off).
- **Swift:** `ReelOps.swift`'s builder; the submenu in `AppDelegate+ClipMenus.swift`; new
  `EditorViewController+Layout.swift` (the role rule, the refusal through the refusal strip);
  `UIMenuTable.swift` and `inventory.json`.
- **MCP mirror:** `switch_layout` as an op tool printed from the core's schema, its handler in
  `AgentServer+Layout.swift` (a `creatorHandlers` row), naming Clip ▸ Camera Layout ▸, declaring
  `scope`.
- **Docs:** spec §6, §9; `canvas-and-layers.md` (Camera layouts: how far a switch reaches, the zoom
  refusal and the nest), `menus-and-shortcuts.md`, `mcp.md`; `core/CLAUDE.md` (`layout.rs`,
  `edit_layout.rs`); `docs/manual-checks.md` (JOB-63); root `CLAUDE.md`'s product count.
- **Acceptance:** core tests; proof rows; `make gate`.
- **Proof** (`co6_proof.py`, Release; probes): L1 each layout lands its end, all six keys, at the
  core's numbers on 1920×1080 and 1080×1920; L2 a switch at a first frame writes base props and a
  one-frame layout action equal to them; L3 after three cuts a switch on the second clip carries to
  the third and fourth and stops at a fifth whose first frame holds a layout action; L4 two switches
  on one long clip: two layout actions, the second holding from its end; L5 a later clip whose
  layout action starts mid-clip takes the new base for its head and keeps its action; L6 a later
  screen clip with a zoom is refused naming the clip and action, and with `nest: true` it is nested
  and the zoom still fills the nested box (frame compare); L7 the camera clip at the playhead inside
  an existing action is refused naming it; L8 `through` ends the reach, a clip after it
  byte-unchanged; L9 one undo restores the project; L10 Circle's crop square with radius half the
  side, Rounded's radius the documented fraction, a nest-clip camera refusing both; L11 (probe)
  `ActionBands.isZoom` false and `is_layout` true for every action L1 wrote, `is_zoom` agreeing with
  `isZoom` on CU7's Z5 ends and these.
- **Mutants** (7): the reach stopping at a later zoom instead of refusing (L6); the reach running
  past a layout action (L3); the reach stopping at the first later clip (L3); a layout action
  written without an unchanged key (L11); the head marker left out (L2); `through` ignored (L8);
  circle's radius from the uncropped side (L10).
- **Manual check:** **JOB-63** — on S-ST1, each switch's eased move reads as deliberate at 0.5 s.
- **Depends on:** CO0, CU7 (`action_class.rs`). **Lane** B.
- **Questions for the owner:** (1) Default switch length? *Recommended: 0.5 s, ease in and out.* (2)
  CO-62's offer versus nesting the screen automatically on the first switch? *Recommended: the
  offer* — a nest changes how every later edit of the screen works and should be seen being made.

### SW0 — measuring several 4K angles

Bet 5 opens here. Its switching phases run last in lane C, its audio-track phases at the end of lane
A, and SW7a in lane B. SW-3 (multicam as a program track) was recorded at CJ0a. Nothing in this bet
needs a key: the switch reads the loudness and speech caches and, in SW8, CJ3's faces. SW amends
none of §11's decisions that implement a lifted non-goal: nest clips keep having no in point, there
is one kind of track, and the effect vocabulary stays closed; it amends the foundations' `async`
rule by one named file (SW-43).

- **What a person gets:** nothing in the app. The owner gets a measured answer to survey decision 8
  for this bet, and agents a dev tool that times the preview's rebuilds.
- **Head:** CJ0a's question 4 answered yes (else SW-2's no applies and SW0 is not built); then SW-S2
  (a)–(c), and (d) on S-LONG1.
- **Toll first:** `Playback.swift` (592), its named seam: `setPreviewQuality` and `recompose()` →
  `Playback+PreviewQuality.swift`, behind an internal read of the player's current item.
- **Decisions (draft):**
  - **SW-1 — The preview's rebuilds are counted and timed, in the dev tools only.**
    `PlaybackRebuildLog` records, per window, each rebuild's start (`Playback.startRebuild`'s
    entry), its build (`finishRebuild`'s success arm) and its landing (the restore seek's landing,
    `Playback+Scope.swift`'s `seekFinished()`) in a ring of the last 256; the three calls sit under
    `#if FRAMEJOB_DEV_TOOLS`. The dev tool `playback_rebuilds {reset?}` answers the count and each
    rebuild's `built_ms` and `landed_ms` since the last reset.
  - **SW-2 — SW-S2 runs only after the owner answers survey decision 8, on fixtures built from
    repeats.** With a no, SW0 and SW2c are not built and SW9a ships with every cell refreshed only
    when paused, the guide saying several angles' playback is unmeasured.
- **Swift:** new `PlaybackRebuildLog.swift`; its calls in `Playback.startRebuild`, `finishRebuild`
  and `Playback+Scope.swift`; new `AgentServer+PlaybackRebuilds.swift` (the dev tool, registered
  with the dev tools, not in Distribution).
- **MCP:** the dev tool `playback_rebuilds`.
- **Docs:** spec §7.9c; `tools/proof/README.md` (the tool, F-4K's `ffmpeg` lines, `--build-4k` and
  `--long`); SW-S2's verdict here; root `CLAUDE.md`'s dev tool list; `tools/proof/dev_tools.py`'s
  count (one more, `playback_rebuilds`).
- **Acceptance:** `make gate`; SW-S2's verdict recorded; the proof against Release.
- **Proof** (`rebuild_log_proof.py`, Release): R1 one `set_clip` makes exactly one entry with
  `built_ms` ≤ `landed_ms`; R2 `reset: true` answers an empty list and the next edit one entry; R3
  two edits inside one rebuild's flight leave the superseded generation's entry absent.
- **Mutants** (2): an entry recorded at `finishRebuild` for a superseded generation (R3); `reset`
  ignored (R2).
- **Manual checks:** none. **Depends on:** CJ0a (question 4), CJ0c (T8). **Lane** C.
- **Questions for the owner:** (1) Build F-4K (about 34 GB, 30–60 minutes of encoding)?
  *Recommended: yes, once.* (2) Run (d) on a generated three-hour file (about 68 GB, 1.5–3 hours) or
  wait for S-LONG1? *Recommended: wait for S-LONG1.*

### FC9 — vertical shorts, and the owner's trial

- **What a person gets:** Make Short's Shape row (9:16, 4:5, 1:1, Keep) goes live: each short is
  reframed by VR's step before its captions are laid out, so they measure on the vertical canvas.
  Then the owner runs Find Clips on a real long recording and records a verdict.
- **Decisions (draft):** **FC-90 — The vertical step is VR3's `VerticalVersion.apply(to:shape:…)`
  applied to the short's own document as one undo step "Make Vertical" (VR-30, VR-31),** with
  `captions: false` (VR-40) and graphics re-laid by VR4; 9:16 by default, 4:5, 1:1 or Keep. **FC-91
  — The owner's verdict on Find Clips**, recorded after the trial as GR-1 recorded grading's:
  whether the picks were the moments the owner would have chosen, whether the reasons were true,
  what cost it showed.
- **Swift:** new `ShortMaker+Vertical.swift` (FC-90); the sheet's Shape row live; `make_short`'s
  `shape` accepts `9:16`, `4:5` and `1:1`.
- **MCP mirror:** `make_short.shape`.
- **Docs:** `find-clips.md`; the README highlight completed; FC-91;
  `docs/manual-checks.md` (JOB-44).
- **Acceptance:** the proof against Release; `make gate`; the trial.
- **Proof** (`make_short_vertical_proof.py`): the short's canvas 1080×1920 (or 1080×1350,
  1080×1080); VR's actions present in `get_project`; caption pages measuring at most 0.86 of the
  vertical width; `render_frame` at a caption's word shows the page inside the frame; `shape:
  "keep"` byte-identical to FC8a's in `get_project`.
- **Mutants** (3): vertical after captions; shape ignored; `keep` reframed.
- **Manual check:** **JOB-44** — the owner's trial: Find Clips on one real long recording (S-PC1 or
  S-LONG1; a guest's recording only with their agreement), ten shorts made and watched on a phone;
  the verdict is FC-91.
- **Depends on:** FC8b, VR3, VR4. **Lane** A.
- **Question for the owner:** the default shape? *Recommended: 9:16* (Shorts, Reels and TikTok).

### CO7 — the Layout section, the nest offer and the crop on the person

- **What a person gets:** a **Layout** section in the camera clip's Picture sub-tab (a Layout
  pop-up, Corner and Shape pop-ups, a Duration field, Switch at Playhead). CO-62's refusal becomes a
  sheet with Nest and Switch / Cancel. The circle, side-by-side and stacked crops centre on the
  person when the clip has masks.
- **Decisions (draft):** **CO-70 — The camera crop is centred on the person.** The op takes `focus`
  (a point in the camera's source pixels, `edit_zoom.rs`' Q frame) and centres on the source when it
  is absent. The menu, the section and the `switch_layout` TOOL pass the mean centroid of the camera
  clip's cached masks when they exist; the tool fills it when the caller omits it (declared in
  `AgentCatalog+Declarations.swift`), so an agent's one call equals the menu's; `analyze_cutout`
  answers the same `centroid`. **CO-71** the section's rows.
- **Swift:** new `VideoPane+Layout.swift` (registered for a single selected media clip); new
  `LayoutOfferSheet.swift` (after R5-3's shift sheet); `AgentServer+Layout.swift` fills `focus` from
  CO3's centroid over `MaskPack`; its row in `AgentCatalog+Declarations.swift`.
- **MCP mirror:** none new; the declaration row, and the catalog row names the section.
- **Docs:** spec §4.3b, §7.9a; `canvas-and-layers.md`; `screens.py` screens for the section and the
  sheet.
- **Proof** (`co7_proof.py`, Release; harness): P1 Switch at Playhead sends the op the menu sends;
  P2 with masks of a person left of centre the circle's crop centre is the masks' centroid within a
  pixel; P3 without masks it is the source centre; P4 the sheet's Nest and Switch is one undo step;
  P5 `switch_layout` without `focus` makes the project the menu makes.
- **Mutants** (3): the focus read from a window not wholly analysed (P2 on a half-analysed clip); the
  sheet's two edits as two steps (P4); the tool leaving `focus` empty (P5).
- **Acceptance:** the proof against Release; the screens captured; `make gate`.
- **Manual checks:** none beyond JOB-63. **Depends on:** CO6, CO1. **Lane** B. **Questions:** none.

### VR5b — a screen and its camera re-laid in a vertical version

- **What a person gets:** in Make Vertical Version, a screen recording and its camera arranged with
  Clip ▸ Camera Layout ▸ keep their arrangement: each switch is solved again for the tall canvas,
  Side by Side becoming Stacked, so the screen's two-thirds and the camera's third are not squeezed
  and the screen is not reframed on a subject or the cursor.
- **Decisions (draft), amending VR-33 and VR-34 before the code:**
  - **VR-53 — A layout role is re-laid, not reframed.** VR-33 gains class 2b, checked after class 2
    and before class 3: a clip any of whose actions `action_class::is_layout` recognises is a
    layout role (CO-63), and the front role of a switch is its camera, the role behind it its
    screen (CO6's rule). `reframe_clip`'s `follow` gains `layout`: on the camera clip it reads each
    layout action of both roles, recognises it with `layout.rs`'s new pure `recognise(end, role,
    canvas, source sizes)` (the layout, shape and corner whose solve on the authored canvas,
    `from_width` × `from_height`, equals the end within 1 px in x, y, crop and radius and 0.001 in
    scale and opacity), removes the roles' layout actions and replays the switches in time order
    on the current canvas through `edit_layout.rs`'s composition (its helpers `pub(crate)`), each at
    the old action's `at`, `duration` and `curve`, `through` the next switch's start, with
    `side_by_side` replayed as `stacked` when the canvas is taller than wide (a square keeps it),
    and `focus` as CO-70 fills it. A role whose layout action is not recognised (edited by hand)
    is refused by `follow: layout` naming the action; the step then keeps both roles (`keep`) and
    lists them "a layout edited by hand". VR-34 gains step 3b, after classes 1 and 2: one
    `reframe_clip {follow: "layout"}` per camera, the screen marked done. A re-laid role is never
    followed (classes 3 and 6, VR-51) and gets no backdrop.
  - **VR-54 — The summary and the answer** list each re-laid switch ("re-laid: Side by Side →
    Stacked at 0:42"), and `make_vertical_version` answers `relaid` with them.
- **Core:** `layout.rs` (`recognise`); new `reframe_layout.rs` (≤ 400: `follow: layout`'s replay);
  `edit_layout.rs` (helpers `pub(crate)`); `edit_reframe.rs` (the arm); `op_table.rs`'s `Follow`
  kind gains `layout` (its `values()` row; `op_schema.rs` unchanged). Tests `core/tests/layout.rs`
  (recognise round-trips every layout, shape and corner on 16:9; an end with one key changed is not
  recognised) and `core/tests/reframe_layout.rs` (three switches replayed on 9:16 and 1:1; `through`
  keeping each reach; a hand-edited action refused).
- **FFI:** none.
- **Swift:** `VerticalVersion.swift` (class 2b, step 3b, the summary's re-laid list);
  `AgentServer+VerticalVersion.swift` (`relaid`).
- **MCP mirror:** `reframe_clip`'s `follow` vocabulary prints from the op table; its prose names
  Make Vertical Version as the path; `make_vertical_version`'s answer gains `relaid`.
- **Docs:** `vertical-and-framing.md` (camera layouts in a vertical version),
  `canvas-and-layers.md`; spec §6c (`follow: layout`); VR-33's and VR-34's amendment lines;
  `core/CLAUDE.md` (`reframe_layout.rs`, `recognise`); `docs/manual-checks.md` (JOB-39).
- **Acceptance:** core tests; the proof against Release; `make gate`.
- **Proof** (`vr5b_proof.py`, Release; a CO6 fixture: a screen and a camera at 1920 × 1080 with
  three switches, Corner, Side by Side and Camera Full): R1 the 9:16 copy holds, per role, three
  layout actions at the old starts, durations and curves, each end equal to `switch_layout`'s
  solve on 1080 × 1920, Side by Side's as Stacked's; R2 the 1:1 copy keeps Side by Side; R3 no role
  clip gets reframe actions or a backdrop, and the screen under Corner is not followed; R4 a layout
  action with one key changed by hand is refused by `reframe_clip {follow: "layout"}` naming it,
  and Make Vertical keeps and lists both roles; R5 `render_frame` at the middle of each layout in
  the 9:16 copy equals, byte for byte, a project built at 1080 × 1920 with the same three switches;
  R6 the summary and `relaid` list three re-laid switches.
- **Mutants** (4): class 2b after class 3 (R3); Side by Side kept on a tall canvas (R1); the
  recognition tolerance widened so a hand-edited end is re-laid (R4); `through` dropped so a replay
  reaches past the next switch (R1).
- **Manual check:** **JOB-39** — S-ST1 with its camera in Side by Side, made vertical: the stacked
  version reads well on a phone.
- **Depends on:** VR3, CO6, CO7 (`focus`). **Lane** B.
- **Question for the owner:** Side by Side becomes Stacked on a tall canvas? *Recommended: yes*
  (two-thirds of a 1080-wide frame shows a screen too small to read).

### SW1 — copy pieces to a track, and Switch Angle

- **What a person gets:** Clip ▸ Switch Angle ▸ on a shot lists the camera tracks that cover it and
  swaps the shot to one, in sync, with its dissolves kept, as one undo step. Agents get
  `copy_pieces`, the primitive the switch writes with.
- **Decisions (draft):**
  - **SW-10 — The switch writes a program track; it does not cut the cameras in place.**
    Picture-only cuts on the stacked cameras make two to three clips per shot where the program
    track makes one (a four-camera three-hour show at 8 s shots is about 5,400 against 1,350, past
    `MAX_CLIPS`); moving one cut there is trimming pieces on several tracks, here an ordinary roll;
    both decode one camera at a time.
  - **SW-11 — `copy_pieces {clip, track, ranges, video?, audio?}`** copies the pieces of `clip`
    between each range's ends onto `track` at the same times, with fresh ids. `ranges` are project
    times, each end snapped as `split` snaps; sorted, not overlapping, inside the clip. `video` and
    `audio`, when given, set each piece's `enabled` switches. Refused in its own sentence: a nest
    clip ("clip N is a nest: a piece of it would replay the nest from its first frame"); a range
    outside the clip; overlapping ranges; a locked destination; a destination holding a clip over a
    range ("track T holds clip C between A and B"). `Err` for an unknown clip or track; an empty
    `ranges` an identity. A copy has no transition and its link is cleared. Allowed inside a nest.
  - **SW-12 — A piece is exactly the middle a `split` at its two ends would leave:** source window,
    a ramp's map and rate (SR-18), its actions clipped, a graphic's `in` and `length` (G-9), its
    words rebased (W-3), all from `split_clip`'s own arithmetic on a scratch copy
    (`edit_split.rs:95`).
  - **SW-13 — An angle is a TRACK; Clip ▸ Switch Angle ▸ re-picks one shot.** A track COVERS a span
    when its media clips with pictures together leave no part of it uncovered (a clip with its
    picture off or on a hidden track still counts). The submenu lists, for the one selected clip,
    every other track of its container covering the clip's whole span, front first, by name, up to
    nine; choosing one re-picks by SW-14's sequence, one `copy_pieces` per angle clip the span
    crosses, as one step "Switch Angle". `switch_angle {clip, angle}` does the same and refuses an
    angle not covering the shot, naming the first uncovered tick.
  - **SW-14 — A re-picked shot keeps its span, its switches and both its transitions, and nothing
    else** (a punch-in, grade or action on the old shot does not carry). With B between A and C:
    record B's span, switches and `transition_in`, A's end and C's start and `transition_in`;
    `delete` B; `trim_end` A to B's start and `trim_start` C to B's end, each `alone`; `copy_pieces`
    the angle over B's span with B's switches; trim A and C back to their old edges, re-forming both
    overlaps as they were; `set_transition` and `set_transition_style` give the new piece B's
    `transition_in` and C its own. When the angle's clips cut the span into pieces and an overlap
    would break the overlap rule against a short piece, that transition is dropped and the step is
    "Switch Angle (transition removed)".
- **Core:** new `edit_pieces.rs` (≤ 400, on `split_clip`); its `edit.rs` and `op_rows.rs` rows
  (`op("copy_pieces", &[req("clip", Id), req("track", Id), req("ranges", Ranges), opt("video",
  Boolean), opt("audio", Boolean)])`); allowed in `refused_inside`. `core/tests/copy_pieces.rs`
  (each piece equal to the middle of two splits — plain, ×1.25, ramped, reversed, a graphic, a timed
  text page, with actions; every refusal; snapped ends; switches; links cleared; empty an identity).
- **Swift:** `ReelOps.copyPieces`; new `EditorViewController+SwitchAngle.swift` (SW-13's covering
  rule, SW-14 as one grouped edit, the command and validator); `switchAngleMenu()` in
  `AppDelegate+ClipMenus.swift` with a `SwitchAngleMenuFiller` filling it on open (as
  `LookMenuFiller` does); the row in `clipMenu()`; `UIMenuTable.swift` and `inventory.json`.
- **MCP:** `copy_pieces` printed from the op table; `switch_angle {clip, angle}` in new
  `AgentServer+Switch.swift` (a `creatorHandlers` row) and `AgentCatalog+Switch.swift`, naming Clip
  ▸ Switch Angle.
- **Docs:** spec §6b (split by subsection first if past ~500), §7.9e, §9; `docs/guide/multicam.md`
  (new, "Podcasts and several cameras") and its README row; `menus-and-shortcuts.md`, `mcp.md`; the
  counts.
- **Acceptance:** a piece of a synced angle shows the angle's own frame at every time; Switch Angle
  is one step, keeps the shot's span and the dissolves at both edges.
- **Proof** (`switch_pieces_proof.py`, Release): P1 `copy_pieces` of a ×0.999 drift-corrected angle
  onto a new track: `render_frame` at five times byte-identical to the angle shown alone; P2 Switch
  Angle by `perform_menu_item` replaces the shot's media over the same span and one undo restores
  it; P3 `switch_angle` the same, a non-covering angle refused in its sentence, and an angle of two
  abutting files re-picking a shot crossing their join as two pieces; P4 a shot with a dissolve on
  its incoming edge, its outgoing edge and both: every overlap's span, kind, curve and audio shape
  read back equal, and a two-piece re-pick breaking the overlap rule named "Switch Angle (transition
  removed)"; P5 `copy_pieces` of 1,000 ranges on a two-hour angle within 0.5 s (median of five; over
  it, the figure in the guide and a Performance candidate issue).
- **Mutants** (6): the piece's `in` without the clip's speed (P1); the occupancy refusal removed
  (core); the link kept on the copy (core); candidates not required to cover (P3); delete and copy
  as two steps (P2); neighbours not trimmed back (P4).
- **Manual checks:** none. **Depends on:** SW0 (or SW-2's no), CJ0b (T1), CJ0c (T5, T8). **Lane** C.
- **Questions for the owner:** (1) Keys for Switch Angle now (⌥1–⌥9)? *Recommended: no*; bare 1–9
  come with the viewer in SW9b. (2) Should a re-pick keep the shot's own video settings?
  *Recommended: no* (SW-14).

### SW3a — every audio track of a file, played

- **What a person gets:** a file with several audio tracks imports all of them. The Media tab says
  how many; the Sound tab's Source section picks which track a clip plays. A clip on another track
  says it is not measured yet, until SW4a/SW4b.
- **Head:** SW-S1 runs; its verdicts recorded in SW-30, SW-33 and SW6's branch.
- **Tolls first:** `evaluate.rs`'s `Segment` → `plan_segment.rs`, unless CO2a1 or SW2c paid it;
  `AudioDynamicsLevels.swift`'s leveller curves (257–393) → `AudioDynamicsLevels+Curves.swift`.
  (`ClipSnapshot.swift`, `MediaImporter+Thumbnails.swift`, `model_media.rs`, `edit_described.rs` and
  `op_rows.rs` are CJ0's.)
- **Decisions (draft):**
  - **SW-30 — `media.audio_streams` (format p).** One entry per audio track in AVFoundation's order
    (SW-S1 (a)), each `{track_id, channels, name?, decodes?}` (`name` from title metadata — OBS's
    track names, Matroska's TrackEntry Name; `decodes` written only when false). EVERY audio track
    is listed, undecodable ones included, so stream k is always the k-th entry; Swift finds a
    stream's track by `track_id`, so no new deprecated call is made. Stream 0 is the track every
    build has read. A track decodes when one buffer comes through an `AVAssetReaderTrackOutput` in
    LPCM (`DecoderSupport.decodesFirstAudioBuffer`). Written for every media with audio from this
    format; a media imported earlier reads as one stream of unknown channels, and `set_audio_source`
    refuses any other stream or channel on it ("media M was imported before Frame Job read its audio
    tracks; relink it to the same file to read them"). `add_media` and `relink_media`'s probe accept
    the key; proofs comparing a media record whole are re-pinned.
  - **SW-31 — `source.stream` and `set_audio_source {clip, stream?, channel?}`.** `Source::Media`
    gains `stream` (default 0, written only when not 0): the source, like `reversed` — every
    structural op copies it, `paste_attributes` never carries it, no action names it.
    `set_audio_source` sets the whole audio source (absent `stream` is 0; from SW6 absent `channel`
    is every channel); it refuses a non-media clip, a media with no audio, a stream the file lacks
    ("media M has 3 audio tracks; stream must be below 3, not 4"), an undecodable stream ("media M's
    audio track 3 does not decode on this Mac") and SW-30's older media; equal is an identity. The
    plan's audio segment carries `stream` when not 0. R2-1 stands.
  - **SW-32 — The 48 kHz copy is keyed by file and stream (amends SY-23):** "the key is
    `path|size|mtime|stream|v<version>`, stream 0 spelling the key it always did, and `audioURLs`
    substitutes per (media, stream)."
  - **SW-34 — Relink refuses a file that lacks what a clip plays**, naming the clips ("clip 12 plays
    audio track 3; the new file has 2"; "clip 12 plays audio track 2, which does not decode in the
    new file").
  - **SW-35 — Until SW4, a clip on a stream other than 0 is unmeasured, and says so:** no waveform;
    every measurement (Normalize, Enhance Voice, Match Audio, Duck by Speech, Remove Silences,
    Synchronize Audio, transcription, Find Clips' sound events, Switch by Speaker) refuses it ("clip
    N plays audio track K, which is not measured yet"); its gate, leveller and de-esser levels read
    UNMEASURABLE, never pending (so an export does not wait 300 s, AU-42); in the core
    `speech_spans` gives it no spans. No reader ever shows track 0's figures for another track.
    Amends the AU-110 duck reader. Switch by Speaker's arm lives in `SpeakerSwitch+Read.swift`,
    which lane C's SW2a creates: whichever of SW3a and SW2a lands second adds it (the arm and
    mutant below), so neither waits for the other; SW4b, which depends on both, lifts it.
  - **SW-36 — The Sound tab's Source section** (spec §4.3d), first in the Sound sub-tab when a
    selected clip's file has more than one audio track: Track (a popup, "Track 2 — Mic"; an
    undecodable track listed, disabled), BASE only, ⊘ inside an action, written through
    `set_audio_source`. The Media tab's row says "3 audio tracks".
  - **SW-37 — The core checks what it stores:** `validate` refuses a `source.stream` at or past the
    media's `audio_streams` (any stream above 0 with none), in `edit_audio_source.rs`'s
    `check_audio_source`, called from `check_clips` (`model_query.rs:401`).
- **Core:** `Media.audio_streams` (`MediaAudioStream`, in `model_media.rs`); `Source::Media.stream`
  (`model.rs`), reaching every exhaustive `Source::Media { media, r#in, reversed }` pattern or
  literal, twelve at `d0661e5d` and none with `..`: `edit_clip.rs:203, :589, :602`,
  `edit_background.rs:300`, and the pattern-then-literal pairs that rebuild a source from its parts,
  where SW-31's "every structural op copies it" must carry `stream`: `edit_edge.rs:92/96` (slip),
  `edit_paste.rs:118/122` and `source_window.rs:180/184, :217/221` (the trims and roll);
  `MEDIA_KEYS` (`edit_track.rs`); new `edit_audio_source.rs` (`set_audio_source`,
  `check_audio_source`; the `op_rows.rs` row `op("set_audio_source", &[req("clip", Id),
  opt("stream", Index)])`); the segment's `stream` (`plan_segment.rs`, set in `evaluate.rs`'s
  `segment_of`); `speech_spans` (`audio_duck_speech.rs`, SW-35); `validate` (SW-37); relink's
  refusal (`edit_relink.rs`, 186); the format bump with `schema_vN.rs` and its paragraph; the
  header's version. Tests `core/tests/audio_source.rs`, including slip, paste, `trim_start`,
  `trim_end`, roll, split and a blurred background on a stream-2 clip, each keeping `stream`.
- **Swift:** the probe fills `audio_streams` (`MediaImporter.swift`'s `probeAsset` keeps its awaits;
  the await-free readers of channels, title and track ID in new `MediaImporter+AudioStreams.swift`;
  `DecoderSupport.decodesFirstAudioBuffer`); `MediaDescriptor.swift`, `MediaSnapshot.swift`; the
  clip's stream decoded beside `ClipSource.media` into `ClipSnapshot.audioSource`
  (`ClipSnapshot.swift`); `PlanSegment.stream`; `CompositionBuilder.firstTrack` becomes
  `audioTrack(of:stream:)` (still the one deprecated call); `assetTrack`, `resolveSource` and
  `audioURLs` keyed by (media, stream); `AudioRateCopy` (SW-32); SW-35's guard at each per-media
  reader's entry (`ClipLoudness`, `AudioDynamicsLevels`, `MediaSpeech`, `DuckSpeech`,
  `SilenceDetector`, `AudioSync`, `Transcriber`, the filler sheet, `MediaPeaks`, FC3's
  `SoundEvents.events(in:for:)` and `AnalysisKind+SoundEvents`' job, TX's `TimelineTranscript`
  and `TranscriptFill`, FC4's `ClipSignals`, and `SpeakerSwitch+Read` when SW2a has landed); new
  `AudioPane+Source.swift` registered first in the Sound sub-tab; `ReelOps.setAudioSource`; the
  Media row's count.
- **MCP:** `set_audio_source` printed from the op table; `get_project` shows `audio_streams` and
  `source.stream`; `import_media`'s prose (`AgentCatalog+Files.swift`) says every track is listed.
- **Docs:** spec §5.2a, §5.2b, §6b, §7.2, §7.7, §4.3d; `audio.md`, `projects-and-media.md`; a screen
  `designs/screens/09d-clip-sound-source.md`; both `CLAUDE.md` maps; the tolls' history entries.
- **Acceptance:** each track of a three-track file plays and exports alone; a project without
  streams plays and exports the bytes it did.
- **Proof** (`audio_streams_proof.py`, Release; F-MULTITRACK): A1 import lists three streams with
  ids, channels and names, an undecodable track `decodes: false`; A2 each stream exported as 24-bit
  WAV peaks at its own tone ≥ 40 dB above the others, and the 48 kHz LPCM file's streams null within
  −90 dB against ffmpeg's `-map 0:a:k`; A3 a 44.1 kHz file's streams 1 and 2 at once each identify
  by spectrum and null within −90 dB against an export of the same track extracted with `-c copy`;
  A4 a relink to a two-track file refused naming the clip; A5 `phase5_proof.py`'s fixture exports
  byte-identical to the build before; A6 a stream-2 clip draws no waveform, Normalize refuses it in
  SW-35's sentence, and a gated stream-2 clip exports without waiting; A7 one undo step through the
  Source section (`snapshot_ui`), an undecodable track disabled in its popup; A8 a stream-2 clip
  with a speech duck ducks nothing in the plan; A9 `find_clips` over a stream-2 clip refuses it in
  SW-35's sentence and `get_media_analysis {kind: "sound_events"}` is not asked for it; A10 (when
  SW2a has landed) Switch by Speaker with a stream-2 microphone refuses it in SW-35's sentence.
- **Mutants** (8): the lookup ignoring the stream (A2); the copy key without the stream (A3); the
  relink check removed (A4); SW-35's guard removed in `ClipLoudness` (A6); a stream-2 level answered
  pending (A6); `speech_spans` reading `media.speech` for every stream (A8); slip's rebuilt source
  dropping `stream` (core test); SW-35's guard removed from `SoundEvents` (A9). Whichever of SW3a
  and SW2a lands second also runs one more: the guard removed from `SpeakerSwitch+Read` (A10).
- **Manual checks:** none (A2 and A3 measure the sound).
- **Depends on:** CJ0b (T1, T2, T4), CJ0a (T10), CJ0d (T12, T16), TX7, FC3 (`SoundEvents`); SW-S1.
  **Lane** A. Not SW2a: SW-35's Switch by Speaker arm goes with whichever lands second.
- **Questions for the owner:** (1) Which track plays by default? *Recommended: track 1* (every build
  plays it; OBS puts its mix there). (2) Ask anything at import? *Recommended: no.*

### CO8 — layout and cutout at record time

- **What a person gets:** with "Record the camera too" ticked, the recorder panel shows a Layout
  pop-up (Corner, Rounded Corner, Circle, Side by Side, Camera Full) and "Remove the camera's
  background when it lands". The camera lands in that layout, and its background is removed as the
  next undo step. No clip placed before the recording moves.
- **Decisions (draft):** **CO-80 — The recorder offers a layout**, amending **CAM-10 (3)** ("The
  camera is placed by `switch_layout` at its clip's first frame with the layout the recorder chose,
  bounded by `through` to the recording; `corner`, shape `square`, bottom-right, is today's geometry
  to the pixel"), **CAM-10 (5)** and **CAM-4** (`record_screen` admits `camera_layout` and
  `camera_cutout`, both refused without `camera`, in CAM-4 (2)'s step (3)), and **CAM-11** (two
  panel controls and two keys, `FrameJobRecordingCameraLayout` (absent = `corner_square`, today's
  landing) and `FrameJobRecordingCameraCutout` (absent = false), the panel's next keys after CU's
  sixteen, pinned in the harness and `screens.py`). The landing passes `through` = the recording's
  last frame. **CO-81 — The cutout follows the landing as its own undo step** "Remove Background"
  (AU-68's pattern).
- **Swift:** `RecorderPanelController+Rows.swift` (the two rows) and
  `RecorderPanelController+Choices.swift` (U3's file; the two keys); `RecordingLanding+Camera.swift`
  (`cornerPatch` replaced by one `switch_layout` at each camera clip's first frame, `screen` the
  segment's screen clip, `through` the recording's last frame); new `RecordingCutout.swift` (the
  follow-up).
- **MCP mirror:** `record_screen` admits `camera_layout` and `camera_cutout`; the catalog's
  description (`AgentCatalog+RecordingArguments.swift`) names the panel rows.
- **Docs:** `screen-recording.md`; spec §7.9d; `camera-recording-2.md`'s amendments.
- **Acceptance:** proof rows; the harness and `screens.py` pin the two keys; `make gate`.
- **Proof** (`co8_proof.py`, Release, through `land_recording` at both doors): R1 the default
  landing's camera and screen props read back byte-identical to CAM-10's, each role clip carrying
  one one-frame layout action at its start; R2 each layout lands as `switch_layout`'s base props; R3
  the cutout box lands `video.cutout` as a second undo step; R4 `record_screen {camera_layout}`
  without `camera` refused in CAM-4 (2)'s sentence; R5 the two keys persist across a relaunch and
  the proof restores both, so `mcp.py`'s guard sees no moved key; R6 a landing on an existing front
  track ahead of a clip placed before leaves that clip byte-identical; R7 with `fit_new_clips` off
  the landed screen's props equal today's landing's.
- **Mutants** (3): the cutout folded into the landing's step (R3); the default layout changed (R1);
  `through` left out (R6).
- **Manual checks:** none (landing is measured).
- **Depends on:** CO6, CO3, CU0a (U3, U4), CU10. **Lane** B.
- **Question for the owner:** the panel's default layout? *Recommended: Corner* (today's landing);
  or Rounded Corner, the look creators expect, accepting that R1's pin moves.

### SW2a — the switch's planner and its numbers

- **What a person gets:** nothing visible: the planner that decides the cuts, its readings off the
  document, and defaults tuned on real speech.
- **Head (inside the phase, once the planner exists):** SW-S4 runs; SW-21's and SW-22's defaults
  recorded.
- **Decisions (draft):**
  - **SW-20 — The inputs.** Angles are tracks (SW-13): each track holding a selected media clip with
    pictures, two to nine. A microphone is a track: by default each track holding a selected sound
    clip whose MEDIA has no pictures; a camera's own sound counts only when no picture-less sound
    clip is selected (then each angle whose clips play sound is its own microphone); a camera's
    detached sound only when picked in the sheet's Microphone popup or named by the tool. Speakers
    are pairs of a microphone and an angle; by default a microphone that is itself an angle pairs
    with itself and the others pair, front to back, with the remaining angles; the wide is the one
    angle no microphone names, when exactly one is left. The range is the In/Out range, else the
    first selected angle clip's start to the last one's end. A microphone's steps outside its clips
    are silent. The switch trusts the placement and does not check sync (the guide says to run
    Synchronize Audio first).
  - **SW-21 — A microphone is active when its voice is its own.** On a 10 ms grid, for each
    microphone m: its level ℓ_m(k) is 10·log10 of the loudness cache's K-weighted mean square
    through the clip's channel matrix (AU-35) and source map, averaged over a CENTRED 100 ms window
    (k − 5 to k + 4); its voice v_m(k) the speech cache's probability for the 32 ms chunk at that
    step; P_m the 90th percentile of ℓ_m over v_m ≥ 0.5; F_m the 10th percentile over v_m < 0.5. m
    is active when v_m(k) ≥ 0.5, ℓ_m(k) ≥ P_m − `bleed_db` (15 dB) and ℓ_m(k) ≥ F_m + 6 dB; when two
    or more are active and one's ℓ − P exceeds every other's by `dominance_db` (8 dB), only it is.
    Provisional until SW-S4.
  - **SW-22 — Turns become shots.** One active microphone is that person, two or more crosstalk,
    none nobody. A turn bridges gaps under 0.5 s; a turn under `min_turn` (1.0 s) starts no shot;
    crosstalk of `crosstalk_min` (1.0 s) or more shows the wide, or holds the current shot without a
    wide or with `crosstalk: hold`; nobody holds the current shot; a shot starts `lead` (0.2 s)
    before the turn's first active step, frame-snapped; a shot whose angle does not cover its span
    goes to the wide when it covers, else extends the shot before; a shot under `min_shot` (2.0 s)
    merges into the one before (the first into the one after); the range opens on the wide when
    there is one; optional `wide_after` (off) cuts to the wide for `min_shot` once one person has
    held the screen that long.
  - **SW-24 — It refuses, naming every reason at once (SY-1's form):** fewer than two angles; a
    speaker without a microphone; one microphone for two or more speakers ("each person needs their
    own microphone" until SW8); a microphone whose loudness or speech is still being analysed; one
    with no speech found; a stretch no angle covers ("no angle has a picture between A and B"); a
    result past the clip ceiling ("Switch by Speaker would add N clips to M; the most is
    {RC_MAX_CLIPS} — raise the minimum shot", read from the header's define).
  - **SW-25 — The switch reads caches and computes nothing else;** the planner is a pure function in
    `SpeakerSwitch.swift`, probe-callable.
  - **SW-27 — The proof's speech is made on the Mac, its truth measured.** Samantha and Daniel (`say
    -v`) read a scripted turn table (skips by name without either); each voice's SOLO stem is
    written before mixing; each microphone is its speaker at 0 dB plus the other at a set bleed plus
    pink noise; a turn's onset is the first sample of its solo stem above −40 dBFS; a cut passes
    when on the frame grid and within τ of onset − `lead`, τ = 64 ms (two VAD chunks) + 50 ms (half
    the window) + one frame (about 147 ms at 30 fps).
- **Swift:** new `SpeakerSwitch.swift` (pure: SW-20's defaults and pairing, SW-21, SW-22, SW-24),
  `SpeakerSwitch+Read.swift` (readings off the document, AudioSync's `read`; SW-35's stream guard
  and its row and mutant if SW3a has landed first),
  `ClipLevelSeries.swift` (a clip's 10 ms level series through `ClipLoudness.ChannelMatrix` and its
  source map, the centred window); the generator `tools/proof/creator_spike/f_turns.py` (F-TURNS).
- **MCP:** none yet.
- **Docs:** SW-21's and SW-22's defaults and SW-S4's record here.
- **Acceptance:** `make gate`; SW-S4 recorded; the probe PASS.
- **Proof** (`switch_speaker_probe.swift`, scored by `switch_speaker_probe.py`): R1 SW-21 over
  synthetic series, each threshold at its edge, the centred window; R2 SW-22's turns, merges, lead
  and the hand-off to the wide; R3 SW-24's refusals as one list, the ceiling from `RC_MAX_CLIPS`; R4
  SW-20's defaults (picture-less files are the microphones; with none, each camera its own; a
  detached camera sound never a default); R5 a two-file angle covers its join, and a gap in every
  angle is refused naming it; R6 over F-TURNS' readings every cut within τ.
- **Mutants** (5): the bleed test removed (R1); the dominance test removed (R1); a trailing window
  (R6); a short shot merged into the next (R2); a camera's own sound taken beside picture-less files
  (R4).
- **Manual checks:** none. **Depends on:** SW1. **Lane** C.
- **Question for the owner:** the defaults (minimum shot 2 s, cut 0.2 s before speech, wide after 1
  s of crosstalk) as SW-S4 tunes them? *Recommended: yes.*

### SW3b — renders and Reverse read the clip's track

- **What a person gets:** speed ramps, voice isolation, voice effects and Reverse use the track the
  clip plays.
- **Decisions (draft):** **SW-33 — Offline renders read the clip's stream and name it** (amends
  SR-12 (a)'s name, AU-52 and AU-144: "… and the stream, when not 0"). The reversed copy carries
  every decodable track of its source, in order, each reversed (`rendererVersion` bumped), so a
  reversed clip plays its own stream (or a reversed CAF per stream if SW-S1 (e) failed).
- **Swift:** `RampAudioRenderer`, `RampAudioCache`, `IsolationRenderer`, `IsolationCache`,
  `VoiceRenderer`, `VoiceCache`; `ReverseRenderer`, `ReverseRenderer+Audio`, `ReverseCache`
  (`ReverseRenderer+Settings.swift` is CJ0d's T17).
- **Docs:** SR-12 (a)'s, AU-52's and AU-144's lines; `audio.md`.
- **Proof** (rows in `audio_streams_proof.py`): B1 a stream-2 clip with a ramp renders stream 2's
  tone; B2 the same with isolation; B3 with a voice effect; B4 a reversed stream-2 clip's export
  peaks at stream 2's tone and the reversed file holds every track in order; B5 a stream-0 project's
  renders keep their names (none remade).
- **Mutants** (3): a renderer reading the first track (B1); the reversed copy carrying one track
  (B4); a stream-0 name changed (B5).
- **Acceptance:** the proof rows against Release; `make gate`.
- **Depends on:** SW3a. **Lane** A. **Questions:** none.

### CO9 — hide the camera while silent

- **What a person gets:** a **Hide While Silent** section on a picture clip: on/off, Speech from
  (the audio media playing under the clip, the microphone first), Pre-roll, Hold and Fade. The
  camera fades out during pauses and back in just before speech, and the timeline draws the fade
  line on the clip.
- **Decisions (draft):**
  - **CO-90 — Hide while silent is a presentation term.** `video.hide_silent` (format p): `null`, or
    `{media, pre_roll, hold, fade}`. At each instant the core multiplies the layer's placed opacity
    by a gate read from `media`'s saved speech spans in the nearest container — from the layer's own
    outward through its enclosing nest clips — where a clip of `media` plays: 1 while speech plays,
    widened by `pre_roll` before and `hold` after, ramping to 0 over `fade`; 1 where no clip of
    `media` plays in any enclosing container. It reads the media's default source (`media.speech`);
    SW4b adds `stream` and `channel`. Like `video.motion` (R5-4), every edit, `clip_state`,
    `get_project` and the inspector read the clip un-gated; only the recipe and the plan's `gates`
    see it. Not animatable: `set_action_end` refuses it by name, the evaluator restores the base.
    `remove_media` clears every gate naming the media (as a LUT look). Amends **AU-110** ("a second
    reader, `video.hide_silent`, reads a media's spans to show a picture while that media's speech
    plays") and **R5-4** ("`video.hide_silent`'s gate is the third place the recipe draws what the
    model does not say").
  - **CO-91 — Defaults:** pre-roll 0.2 s, hold 1.5 s, fade 0.3 s.
- **Core:** `video.hide_silent` in `model_props.rs`, checks in `cutout_check.rs`; new
  `video_gate.rs` (the gate at a tick through `speech_in_clip`, widened and merged; its ramps for
  `gates`); the multiply where `recipe.rs`'s `moved` runs; `remove_media` clearing gates;
  `edit_action_end.rs`'s refusal; `actions.rs`' base restore (its toll first if needed); the format
  bump and `core/tests/hide_silent.rs`.
- **Swift:** new `VideoPane+HideSilent.swift` (writes the `set_media_speech` the media needs before
  the `set_video` in one step, as Duck by Speech does); `DuckSpeech.swift` (`ops(forMedia:)`,
  refusing when the speech cache is not written); new `TimelineView+GateLine.swift` (drawn after the
  duck line); `CompositionPlan.swift` (`gates`); the frozen `TimelineView.swift` gains `gateCurves`
  beside `duckCurves` (:35), set by one line beside `EditorViewController+Timeline.swift:75` and
  drawn by one call in `TimelineClipDrawing.swift` after :129.
- **MCP mirror:** `set_video`'s handler (`AgentServer+Properties.swift`) reads `hide_silent.media`
  and prepends `DuckSpeech.ops(forMedia:)`, refusing in its sentence (as `set_audio` does for
  `duck.mode` `speech`, :59–80); `set_video`'s description names `hide_silent`.
- **Docs:** spec §5.2a, §7.2 (`gates`), §7.3; `canvas-and-layers.md`; AU-110's and R5-4's lines;
  `docs/manual-checks.md` (JOB-64).
- **Proof** (`co9_proof.py`, Release): H1 on known spans the rendered opacity is 1 inside each
  widened span, 0 in a gap longer than pre-roll + hold + 2 × fade, the ramp's midpoint at the
  documented tick; H2 a ripple delete through microphone and camera keeps the gate on the speech; H3
  where no clip of the media plays the camera shows; H4 `clip_state` reads opacity un-gated; H5
  removing the media clears the gate; H6 `video.hide_silent` in an end refused by name; H7 a camera
  nested apart from its microphone is gated by the microphone in the enclosing container; H8
  `set_video {hide_silent}` saves the spans in the same step and refuses when the cache is not
  written.
- **Mutants** (6): pre-roll after the span (H1); the gate stored as times (H2); gated opacity
  leaking into `clip_state` (H4); the refusal dropped (H6); the gate reading only the layer's own
  container (H7); the tool not prepending the spans (H8).
- **Manual check:** **JOB-64** — on S-ST1, the camera leaves and returns at natural moments, with no
  flicker on short pauses.
- **Acceptance:** core tests; the proof against Release; `make gate`.
- **Depends on:** CO0; CO2a1 (`edit_action_end.rs`, `cutout_check.rs`, which this phase edits).
  **Lane** B.
- **Question for the owner:** fade, or a Screen Only layout on silence? *Recommended: fade* — a
  silence-driven layout switch would write actions and fight CO-61's switches.

### SW2b — Clip ▸ Switch by Speaker…

- **What a person gets:** Clip ▸ Switch by Speaker… over synced cameras and microphones. The sheet
  lists each microphone with a Camera popup, a Wide popup, Minimum shot, Cut before speech,
  Crosstalk shows (Wide or Current speaker), an advanced Ignore bleed row, "Mute the cameras' own
  sound" and, when a previous Program track qualifies, Replace the shots on. Switch writes the
  Program track as one undo step.
- **Decisions (draft):**
  - **SW-23 — What the switch writes, as one undo step "Switch by Speaker".** A new track "Program"
    directly in front of the front-most angle track (`add_track` at that index); one `copy_pieces`
    per angle CLIP a shot crosses, ranges cut at the clip's ends, `video: true, audio: false`; the
    angles hidden without touching anything outside the range — a track is hidden only when every
    clip on it is an angle clip wholly inside the range; otherwise each angle clip straddling a
    range end is `split` there and each angle clip or piece inside has its picture off (`set_enabled
    {video: false}`). "Mute the cameras' own sound" puts `set_enabled {audio: false}` on every angle
    clip inside the range that is not also a microphone (by the same split rule); on by default when
    no microphone is an angle. Microphones are never edited. With `track` ("Replace the shots on")
    it writes onto that track after a `lift_range`-style clear of it alone over the range.
  - **SW-26 — The sheet and the tool take the same arguments:** `switch_by_speaker {speakers: [{mic,
    angle}], wide?, from?, to?, min_shot?, min_turn?, lead?, crosstalk?: "wide"|"hold", bleed_db?,
    dominance_db?, wide_after?, mute_cameras?, track?, apply?}` (track ids); `apply: false` answers
    the shots and the ops' count without editing; with no `speakers` the tool applies SW-20's
    defaults over the selection.
  - **SW-28 — reserved for SW2c. SW-29 — the owner's verdict on a real episode (JOB-51).**
- **Core:** nothing new (`add_track`, `copy_pieces`, `split`, `set_track`, `set_enabled`).
- **Swift:** new `SwitchSpeakerSheetController.swift`, `EditorViewController+SwitchSpeaker.swift`
  (the command, SW-23 as one grouped edit, the validator: two or more selected clips with pictures
  on two or more tracks and one or more with sound); the row after Synchronize Audio in
  `clipMenu()`; `UIMenuTable.swift` and `inventory.json` rows; `-RCDevSwitchSpeakerAccept YES` (dev
  only) presses Switch with the sheet's values.
- **MCP:** `switch_by_speaker` (SW-26) in `AgentServer+Switch.swift`, declaring `scope`, naming Clip
  ▸ Switch by Speaker….
- **Docs:** `multicam.md` (Synchronize Audio, then Switch by Speaker, then Switch Angle and rolls;
  which tracks count as microphones; bleed and Ignore bleed; slip and move break sync); the README
  highlight; `menus-and-shortcuts.md`, `mcp.md`; spec §7.9e, §9, §10's acceptance step; a screen
  `19-switch-by-speaker-sheet.md` (provisional); `docs/manual-checks.md` (JOB-51, JOB-52); root
  `CLAUDE.md`'s dev launch defaults (`-RCDevSwitchSpeakerAccept`); the counts.
- **Acceptance:** on F-TURNS every cut on the grid within τ; bleed never cuts; crosstalk shows the
  wide; the microphones' sound unchanged; the timeline outside the range unchanged; one undo step.
- **Proof** (`switch_speaker_proof.py`, Release; F-TURNS): S1 the shots against the turn table; S2
  bleed at −12 dB with `bleed_db` 15 makes no shot of the silent person; S3 `render_frame` at each
  turn's middle shows that person's card colour; S4 an export of the mix decoded is sample-identical
  before and after; S5 one undo step and the ops' shape (one track in front, one `copy_pieces` per
  angle clip, angle tracks hidden); S6 `apply: false` answers the same shots and changes nothing; S7
  a microphone still analysing and a too-small minimum shot over a long range refused; S8 with a
  range inside the angles, `render_frame` at three times before and three after the range
  byte-identical, angles straddling the ends split there; S9 F-TURNS' two-file angle: shots crossing
  its join are two pieces and play its frames; S10 Clip ▸ Switch by Speaker… by `perform_menu_item`
  with `-RCDevSwitchSpeakerAccept YES` and Minimum shot set to 3 s gives, in `get_project`, the
  project `switch_by_speaker {min_shot: 3 s}` gives over the same selection on a copy.
- **Mutants** (7): `min_turn` ignored (S1); crosstalk never showing the wide (S1); `lead` subtracted
  twice (S1); the snap removed (S1); the ceiling check removed (S7); a whole track hidden when the
  range covers part (S8); the sheet's Minimum shot not passed (S10).
- **Manual checks:** **JOB-51** — Switch by Speaker on a real episode (S-PC1, ten minutes or more,
  Synchronize Audio first, the defaults): each cut just before the new speaker's first word, no cut
  on a short reply, the wide while both talk, no cut to a silent listener; the verdict is SW-29.
  **JOB-52** — playing the Program track over thirty cuts at 4K: no visible hitch, the sound
  uninterrupted.
- **Depends on:** SW2a, CJ6. **Lane** C.
- **Questions for the owner:** (1) The program track rather than cutting the cameras in place?
  *Recommended: the program track.* (2) `wide_after`? *Recommended: offered, off by default.* (3)
  Cut to the wide on laughter (FC's `sound_events`)? *Recommended: not here; a candidate issue.*

### SW4a — every track's caches

- **What a person gets:** a clip on any track of a file has its own waveform, and the loudness, sync
  and speech caches every later reader needs are made for it, started when a clip's track changes
  without reopening.
- **Tolls first:** `ProjectDocument.swift`'s `generateCaches()` (811–826) →
  `ProjectDocument+Caches.swift`; SW-43 recorded, then `MediaImporter.swift`'s four audio passes
  (443–588) → `MediaImporter+AudioPasses.swift`.
- **Decisions (draft):**
  - **SW-40 — An audio source is (media, stream, channel), and every audio cache is per source.**
    Its key spells `<id>` for stream 0 with every channel (today's names, so nothing is rebuilt),
    `<id>s<k>` for another stream and, from SW6, `<id>s<k>c<c>` for one channel. Amends **AU-10**
    (`cache/loudness/<key>.bin`), `silence.md`'s speech-cache bullet (a per-SOURCE cache), **SY-11**
    and `audio-sync-2.md`'s first-track sentence (the pass reads the source's stream, from SW6 its
    channel), **R6-3** (one upload per audio source; `cache/transcripts/<key>.json`), the device
    transcripts' name (`<key>-<language>.json`), and **FC-31** with **CJ-22** for the one analysis
    kind that reads sound: `sound_events`' marker and payload are keyed by `AudioSourceKey`
    (`cache/analysis/sound_events/<key>.json`, its `windows.bin` in `<key>/`), the stream read
    through the source's track and from SW6 its channel, and its `AnalysisStamp` names the stream
    and channel (a picture kind's stamp is unchanged). `MediaCacheLoader`, the cache posts and
    `CacheLedger`'s per-file passes take the key.
  - **SW-41 — Which sources are made, and when.** Every media with audio gets its default source
    first, as today; any other source when a clip of the project, in any container, plays it, after
    the default and in stream order; a source no clip plays any more is pruned at the next pass. The
    wanted set is computed from the snapshot; `startCaches`' `.projectDocumentDidChange` observer
    starts a pass for each media whose wanted sources changed (as for a changed Camera Log, GR-21).
  - **SW-43 — `MediaImporter`'s audio passes may live in one more named file** (amends the
    foundations rule): "`MediaImporter+AudioPasses.swift`, an extension of the same type, holds the
    peaks, loudness, sync-features and speech passes with their awaits; a named file, not a licence:
    nothing else gains `async`."
  - **SW-44 — A derived project copies every source's caches (amends CJ-51):** "each kept media's
    caches are copied under every key it has: `<id>`, `<id>s<k>` and `<id>s<k>c<c>`."
- **Swift:** new `AudioSourceKey.swift`; `MediaCacheFiles.swift` names through it;
  `MediaCacheLoader` keyed by it (`MediaPeaks.swift`); the four passes take a key
  (`MediaImporter+AudioPasses.swift` with `+Peaks`, `+Loudness`, `+SyncFeatures`, `+Speech`);
  `AnalysisKind+SoundEvents.swift` and `SoundEvents.swift` keyed by source (the job decodes the
  source's track; the stamp gains the stream and channel; SW-35's guard on them lifted in SW4b);
  `generateCaches(for:)` per wanted source; the wanted set in `ProjectDocument+Caches.swift` and the
  observer in `ProjectDocument+ConvertedThumbnails.swift`; posts and `CacheLedger` per key; the
  prune; the waveform in `TimelineClipDrawing.swift` by key (SW-35's guard lifted for the waveform
  only); `ProjectDocument+Derived.swift` (SW-44).
- **Docs:** spec §5.6; SW-40, SW-41, SW-43, SW-44 and their lines (FC-31's and CJ-22's included);
  `app/CLAUDE.md` (the named async file).
- **Acceptance:** a stream-2 clip's waveform is stream 2's; stream 0's cache files keep their names
  and bytes; choosing a track makes its caches with no reopen.
- **Proof** (`audio_streams_cache_proof.py`, Release; F-MULTITRACK with speech placed differently
  per track): C1 `cache/peaks/<id>s2.bin` exists with track 2's levels; C2 after `set_audio_source`
  to stream 2 on an open project the waveform, loudness, sync and speech caches for `<id>s2` land
  without a reopen; C3 the default source's files byte-identical to the build before; C4 a stream no
  clip plays any more is pruned at the next pass; C4b `sound_events` run on F-MULTITRACK's stream 0
  and stream 2 writes `cache/analysis/sound_events/<id>.json` and `<id>s2.json`, each stamp naming
  its stream, and with canned events (CJ-26) of laughter on stream 2 only, `find_clips` over a
  stream-2 clip reads the laughter and over a stream-0 clip of the same media reads none.
- **Mutants** (5): the key without the stream (C1); the wanted set without other streams (C1); the
  observer not starting a pass (C2); the prune removed (C4); `sound_events` keyed by media (C4b).
- **Depends on:** SW3b. **Lane** A.
- **Question for the owner:** measure every track at import, or only tracks a clip plays?
  *Recommended: track 1 always and the others when played* (a six-track OBS file would otherwise
  cost six passes).

### SW7a — link groups

- **What a person gets:** a picture and two or more sound clips move, cut, trim, slip and ripple as
  one, with the link glyph and echo ring on each, as a detached pair does today.
- **Tolls first:** `edit_time.rs`'s `freeze_frame` (475–595) → `edit_freeze.rs`;
  `edit_clip_timing.rs`'s speed-profile helpers → `edit_speed_profile.rs` (paid by CU9a); when
  `AgentCatalog+Clips.swift` stands at 580 or more, its edge rows → `AgentCatalog+ClipEdges.swift`.
  (`edit_clip.rs` and `ClipSnapshot.swift` were paid by CJ0b's T4 and CJ0d's T12.)
- **Decisions (draft):**
  - **SW-70 — A link is a group (amends AU-90):** "`Clip.link` (format p) is a group number shared
    by two or more clips in one container; it replaces format 28's `linked`, which the reader
    migrates (a pair becomes a group numbered by the smaller id). A picture and any number of its
    sound clips can move as one."
  - **SW-71 — The rules, generalised (amends AU-91…AU-96):** the closure is every member of every
    named clip's group on an unlocked track; a sound member named alone is deleted alone; a cut
    pairs the cut members' second halves into a new group and each uncut member stays with the half
    it shares more time with (the first on a tie); a trim or roll carries to every member whose same
    edge coincides, unless `alone`; slip moves every member by the smallest clamped amount; speed
    and direction are refused on any member; a shift moves every member of a moved clip's group and
    refuses as today when one would start before 0; Attach Audio merges ONE named sound member and
    leaves the rest grouped; a group of fewer than two in its container is cleared in `finish`;
    copies map group numbers to fresh ones.
  - **SW-72 — The chrome (amends AU-97):** the link glyph on every member; the dashed echo ring on
    every other member of a selected clip's group.
  - **SW-73 — The road map's own link readers move with the shipped ones, in this phase.** SW7a
    lands after each of them (its Depends line), so it converts them rather than leaving a second
    spelling: TX4's `restore_cut` (`edit_restore.rs`: TX-41 (3)'s "when A and its linked partner
    both gain a piece, the pieces are linked by `pair_split_halves`' rule" becomes "when two or more
    members of a group each gain a piece, the pieces form a new group by SW-71's split rule");
    CJ5a's `keep_range` (AU-92's split at an edge and `settle_links` clearing a dropped piece's link
    become the group rules: a dropped member leaves its group, which `finish` clears when it falls
    under two); CU9a's `retime_range` (its linked-pair refusal becomes "a clip in the range whose
    group has a member outside the range", in AU-94's sentence with the group's ids); SW1's
    `copy_pieces` (a copy's `link` cleared, as today). A phase among them that lands after SW7a is
    built on groups from the start.
- **Core:** `edit_link.rs` (335) rewritten for groups, every reader moving with it — `slip`
  (`edit_edge.rs:73`), `shifted` and `shift_clips` (`edit_time.rs:95, :120`), `carried_edge`
  (`edit_link.rs:238`) and its closures in `roll` (`edit_edge.rs:184–189`), `trim_start` and
  `trim_end` (`edit_clip_timing.rs:168–173, :217–222`), `with_links` and `delete_closure`
  (`edit_clip.rs`, `edit_nest.rs:117`, `edit_time.rs:214`), `pair_split_halves`
  (`edit_clip.rs:492`), `relink_copies` (`edit_clip.rs:562`, `edit_nest.rs:330`, `edit_paste.rs:224,
  :483`), `linked_rate_refusal` (`edit_clip.rs:607`, `edit_clip_timing.rs:287`, `edit_action.rs:426,
  :547, :583`, `edit_action_ramp.rs:204`), `settle_links` (`edit_commit.rs:209`), `check_links`
  (`model_query.rs:379`); `attach_audio`; `detach_audio`'s two assignments (`edit_detach.rs:68,
  :72`); and the road map's own readers (SW-73): `edit_restore.rs` (TX4), `edit_keep_range.rs`
  (CJ5a), `edit_retime.rs` (CU9a), `edit_pieces.rs` (SW1). Every line number here is `d0661e5d`'s
  and is re-read with `grep -n` at the phase's start, since the tolls and those phases move them.
  `Clip.link` and the migration; the format bump with `schema_vN.rs`. Tests: every AP9 link test
  re-run on pairs and repeated on a group of three; `keep_range.rs`, `restore_cut.rs`,
  `retime_range.rs` and `copy_pieces.rs` gain a group-of-three case.
- **Swift:** `ClipSnapshot.link` (`ClipSnapshot.swift`) and a `groupMembers` helper; the echo ring
  for every member (`TimelineClipDrawing.swift`, 499); `TrimSession.alone` / `RollSession.alone`
  unchanged; Copy puts every member of a selected picture's group in the payload
  (`EditorViewController+Clipboard`); `detach_audio`'s and `attach_audio`'s catalog prose.
- **MCP:** nothing new; `get_project` shows `link`.
- **Docs:** spec §5.2b, §4.4; AU-90…AU-97's lines; TX-41's, CJ-50's and CU-90's lines where SW-73
  changes their words; `audio.md`'s split edits; `core/CLAUDE.md` (`edit_link.rs`,
  `edit_freeze.rs`, `edit_speed_profile.rs`).
- **Acceptance:** every AP9 behaviour holds for a pair and generalises to a group of three; an older
  project opens with its pairs as groups; the proof against Release; `make gate`.
- **Proof:** `audio_ap9_proof.py` re-run whole on pairs; new rows on a group of three: L1 move, L2
  split, L3 trim carry and `alone`, L4 slip by the smallest amount, L5 a ripple and an insert-time
  shift, L6 Attach Audio of one member, L7 a format-28 project read back as groups, L8 a roll
  carrying to every coinciding member, L9 `restore_cut` of a cut through a group of three restores
  all three pieces grouped, L10 `keep_range` with an edge inside a group of three leaves every kept
  member grouped and a dropped one ungrouped, L11 `retime_range` over a group of three applies and
  over a group with a member outside the range is refused naming it.
- **Mutants** (9), one per rule: the closure, delete's sound-alone rule, split regrouping, edge
  carry, slip's minimum, the shift's group, the rate refusal, `finish`'s clearing of a one-member
  group, `retime_range` accepting a group with a member outside (L11).
- **Manual checks:** none. **Depends on:** CJ0b (T4), CJ0d (T12), TX4, CJ5a, CU9a, SW1. **Lane** B.
- **Fallback split** (if the design pass finds it more than one pipeline): **SW7a1 — groups in the
  core:** `Clip.link`, the migration and format bump, SW-71's rules in every core reader including
  SW-73's, and the core tests (L1–L11 run over MCP with the chrome unchanged); then **SW7a2 — the
  chrome and Copy:** SW-72, `ClipSnapshot.link`, `groupMembers`, the echo ring, Copy's payload and
  the catalog prose.
- **Question for the owner:** groups, or unlinked sound clips that only stay in sync through
  ripples? *Recommended: groups* — an OBS recording trimmed without them leaves its tracks behind.

### SW2c — cuts between files on alternate composition tracks (only if SW-S2 (a) earns it)

- **What a person gets:** no hitch where the program cuts between two long-GOP 4K files.
- **Toll first:** `evaluate.rs`'s `Segment` → `plan_segment.rs`, unless already paid.
- **Decisions (draft):** **SW-28 — The A/B assignment places a timeline track's adjacent clips of
  DIFFERENT media on alternate composition tracks**, so the next file is decoding before its cut;
  adjacent clips of one media stay on one track. A plan change, no format change; it changes every
  project's plan with such cuts.
- **Core:** the assignment; `core/tests/plan_alternate.rs` (a program track, a nest, a ramp, a
  transition; the decoder warning's count).
- **Docs:** spec §7.2; SW-28.
- **Acceptance:** `make gate`; SW-S2 (a) re-run passes its rule.
- **Proof:** SW-S2 (a) re-run on Release; `phase5_proof.py`'s fixture exports byte-identical.
- **Mutants** (1): the alternation applied to clips of one media.
- **Depends on:** SW0's verdict, SW2b. **Lane** C.

### SW4b — every measurement reads the clip's track

- **What a person gets:** Normalize, Enhance Voice, Match Audio, the gate, leveller and de-esser,
  Duck by Speech, Remove Silences, Synchronize Audio, Generate Captions, `get_transcript`,
  `detect_fillers`, the Transcript tab, Find Clips, Hide While Silent and Switch by Speaker all read
  the track the clip plays.
- **Decisions (draft):** **SW-42 — Speech spans per source (format p; amends AU-110).**
  `media.speech` stays the default source's; `media.audio_speech` is `[{stream, spans}]` for any
  other stream (SW6 adds `channel`), written only when non-empty; `set_media_speech` takes `stream`
  (default 0); `speech_spans` reads the clip's source's entry; `validate` checks each entry (its
  stream inside `audio_streams`, not 0, no two for one source, spans by `check_media_speech`'s
  rules); AU-116's relink rule clips or clears each entry. CO-90's `video.hide_silent` gains
  `stream` and `channel` (defaults 0 and none) here.
- **Core:** `media_speech.rs` (96), `audio_duck_speech.rs`, `edit_audio_source.rs`,
  `edit_relink.rs`, `op_rows.rs`; `video_gate.rs` and `model_props.rs` (`hide_silent`'s source); the
  format bump with `schema_vN.rs`. Tests `core/tests/audio_speech.rs`.
- **Swift:** every reader from media id to the clip's key: `ClipLoudness`, `AudioDynamicsLevels`,
  `MediaSpeech`, `DuckSpeech` (its `ops` write `set_media_speech` with the stream),
  `SilenceDetector`, `AudioSync`, `SpeakerSwitch+Read` (SW2a's), TX's `TimelineTranscript` and
  `TranscriptFill`, FC's `ClipSignals` and `SoundEvents` (keyed by SW4a); `AudioDynamicsLevels` and
  `AudioDynamicsLevels+Curves` (after SW3a's toll); transcripts per key (`MediaTranscript`,
  `DeviceTranscriptCache`, `Transcriber+Extract`'s stream, `+Jobs`); SW-35's guard removed from
  every reader SW3a and SW2a gave it.
- **MCP:** nothing new; `get_transcript`, `get_timeline_transcript`, `detect_silence`,
  `detect_fillers`, `normalize_clip`, `enhance_voice`, `match_audio`, `find_clips` and the rest read
  the clip's source, and their prose says so.
- **Docs:** spec §5.2a, §6c; `audio.md`, `cleanup-tools.md`, `captions.md`, `transcript.md`,
  `find-clips.md`, `multicam.md`.
- **Acceptance:** a stream-2 clip's loudness, speech, sync, transcript and sound events are stream
  2's; the proof against Release; `make gate`.
- **Proof** (rows in `audio_streams_cache_proof.py`): C5 Normalize on a stream-2 clip reaches −16
  LUFS ±0.5 measured on the export; C6 Remove Silences' candidates on it match track 2's speech
  table; C7 Synchronize Audio lines it up with a separate file of the same speech; C8 Duck by Speech
  by a stream-2 voice stores `audio_speech` and ducks at track 2's spans; C9 `get_transcript` and
  `get_timeline_transcript` (on device) answer track 2's words; C10 a gated stream-2 clip's level is
  track 2's; C11 `hide_silent` with a stream-2 microphone gates on track 2's spans; C12 Switch by
  Speaker with a stream-2 microphone (F-MULTITRACK's speech placement as a turn table) cuts on track
  2's turns; C13 `find_clips` over a stream-2 clip reads stream 2's sound events (C4b's canned
  laughter).
- **Mutants** (6): Duck by Speech reading `media.speech` for every source (C8); transcripts keyed by
  media (C9); `ClipLoudness` keyed by media (C5); the `validate` entry check removed (core); the
  gate reading stream 0 (C11); `SpeakerSwitch+Read` reading stream 0 (C12).
- **Depends on:** SW4a; CO9 (`video_gate.rs` and `model_props.rs`' `hide_silent`, which this phase
  re-keys); SW2a (`SpeakerSwitch+Read.swift`). **Lane** A. **Questions:** none.

### SW8 — one-microphone shows, from faces

- **What a person gets:** Switch by Speaker works with one microphone between two people and a
  camera on each: Frame Job watches whose mouth moves while someone speaks.
- **Head:** SW-S3 runs; its band decides whether and how SW8 is built.
- **Decisions (draft):**
  - **SW-80 — Faces are CJ3's `faces` kind, read as CJ-30 stores it:** per sample each face's
    rectangle and mouth opening, at CJ-30's rate, through `get_media_analysis`' store in source
    ticks (no ids, CJ-31). If CJ-S2 moved mouth opening into a `mouths` kind, SW8 builds that kind
    on the same grid first. No Vision request of its own; no model bundled.
  - **SW-81 — Mouth activity.** Per angle and sample, the largest face is that angle's person.
    Activity at a step is the standard deviation of that face's mouth opening over the samples
    within 0.5 s centred on the step (five at 10 a second, three at 5). With one microphone a step
    is speech when the microphone's voice ≥ 0.5; the speaker is the angle whose activity is highest
    when it is at least 1.5× the next and above a floor SW-S3 sets; otherwise crosstalk. SW-22's
    shot rules follow.
  - **SW-82 — How sure it says it is**, by SW-S3's band: in the middle band the sheet reads "Faces
    guess who is talking; check the cuts" and `min_shot` defaults to 3 s.
- **Swift:** new `FaceActivity.swift` (SW-81 over the store), `SpeakerSwitch+Faces.swift` (the
  one-microphone mode feeding SW-22); the sheet's one-microphone form; the "still being analysed"
  refusal, with CJ-28's Analyzing sheet when the command wants faces made.
- **MCP:** `switch_by_speaker` accepts one microphone with two or more angles and no pairing; its
  answer says which mode ran.
- **Docs:** `multicam.md`; spec §7.9e; `docs/manual-checks.md` (JOB-55).
- **Acceptance:** as SW-S3's band says.
- **Proof:** a probe of SW-81 over synthetic activity series (thresholds, the 1.5× rule, the window
  at 10 and at 5 a second, the hand-off to SW-22); MCP rows on canned `faces` (CJ-26) that the mode
  runs, places each cut on the canned turns, and refuses an angle without cached faces.
- **Mutants** (3): the ratio test removed; the voice gate removed; the largest-face choice replaced
  by the first face in CJ-31's order.
- **Manual check:** **JOB-55** — S-PC2 through Switch by Speaker: the cuts follow who talks, as
  SW-S3 measured.
- **Depends on:** SW2b, CJ3; SW-S3. **Lane** C.
- **Question for the owner:** proceed at SW-S3's middle band? *Recommended: yes, with SW-82's
  hedge.*

### SW5 — OBS's Matroska: every audio track copied

- **What a person gets:** an OBS `.mkv` with three audio tracks opens with all three, named as in
  OBS.
- **Room first:** `container.rs`' `audio()` builder → `container_audio.rs` if the phase would pass
  400; `ContainerRewrapWriter.swift`'s audio setup → `+Audio.swift` if past 600; `ReelContainer`'s
  change lands in `ReelCore+MediaFiles.swift`.
- **Decisions (draft):** **SW-50 — The rewrap copies every audio track (amends #216-R):** "Swift
  copies the first video stream and EVERY audio stream, in the file's order, each with its Name,
  unchanged; `required_bytes` counts them all; a track whose codec the copy does not carry sends the
  whole file to the opt-in ffmpeg step as before." **SW-51 — `rc_container_sample`'s track argument
  is an index** (0 the video, 1 + k the k-th audio track); `describe` lists the audio tracks as an
  array; three files in lockstep. **SW-52 — The ffmpeg step maps every audio stream** (`-map 0:a?`).
- **Core:** `container.rs`, `container_header.rs`, `container_timing.rs` index every audio track
  (`audio: Vec<Audio>`); `required_bytes`; `ffi_container.rs`. Tests: three-track files (Opus, AAC,
  Vorbis) and one whose second track is undecodable.
- **FFI:** the argument and `describe`'s array (Rust, header, `ReelContainer`).
- **Swift:** `ContainerRewrap.swift`, `ContainerRewrapWriter.swift` (one passthrough input per audio
  track, named); `FFmpegRewrap+Plan.swift:233`.
- **Docs:** spec §7.7; `projects-and-media.md` ("OBS recordings"); #216-R's line;
  `docs/manual-checks.md` (JOB-53).
- **Acceptance:** every audio track of a Matroska file is in the copy, packet for packet.
- **Proof** (`container_rewrap_probe.py` extended, Release): M1 an ffmpeg three-track MKV's copy has
  three audio tracks with byte-identical packets; M2 each plays as its stream (A2's spectrum test);
  M3 the ffmpeg command maps `0:a?`; M4 S-MT1's `.mkv` when supplied.
- **Mutants** (3): the index stops at the first audio track (core); the writer copies one (M1); the
  map back to `0:a:0?` (M3).
- **Manual check:** **JOB-53** — an OBS recording with the microphone on track 2 and the desktop on
  track 3 opens with three tracks named as in OBS, each audible alone from the Source section.
- **Depends on:** SW3a. **Lane** A. **Questions:** none.

### VR6 — a two-shot follows the speaker

- **What a person gets:** a vertical version of a wide two-person shot cuts to whoever is speaking,
  from each person's microphone, agreeing with Switch by Speaker about who that is.
- **Head:** VR-S3 runs (on S-PC3 and the two-face moving still); its threshold recorded in VR-61.
- **Decisions (draft):** **VR-60 — `follow: speaker {mics: [clip ids]}`.** Who speaks when is SW2's
  answer: SW-21's active-microphone rule and SW-22's turns, read through `SpeakerSwitch`'s readings,
  so Switch by Speaker and this framing agree; the app hands the op `turns: [{from, to, mic}]` in
  timeline ticks (`filledByTheApp`); nothing is written to `media.speech`. A face track (VR-21's
  linking) is matched to a mic by the agreement between its mouth opening (CJ-30, smoothed by the
  planner) and the mic's turns, the best assignment over at most four. A mic still being analysed,
  or with no speech, is refused in SW-24's sentence. **VR-61 — Speaker changes are cuts in the
  framing**, held at least 2 s; when both speak, the union if it fits, else the last speaker; under
  VR-S3's threshold the sheet asks which face is which mic, and the tool refuses naming each face
  track and takes `pairs: [{mic, face}]`.
- **Core:** `follow: speaker` in `reframe.rs` over app-filled `turns`; mouth opening from the
  `faces` samples in `Subjects`.
- **Swift:** the handler and the sheet read SW2's turns for the mic clips and fill `turns`; the
  sheet's Follow gains "Speaker", with a mic picker and the face-to-mic question when agreement is
  low.
- **MCP mirror:** `reframe_clip`'s `follow`, `mics` and `pairs`; `make_vertical_version` takes
  `mics`.
- **Docs:** `vertical-and-framing.md`; spec §6c; `docs/manual-checks.md` (JOB-37).
- **Acceptance:** VR-S3 recorded; the proof against Release; `make gate`.
- **Proof** (`vr6_proof.py`): the two-face canned analysis with two synthetic mic clips whose speech
  alternates at known times: the framing switches within one frame of each change that follows a 2 s
  hold, the face-to-mic assignment is the true one, and `media.speech` is unchanged.
- **Mutants** (3): the 2 s hold removed; the assignment transposed; union on both-speak off.
- **Manual check:** **JOB-37** — S-PC3's vertical version follows the speaker.
- **Depends on:** VR3 (`make_vertical_version`, which gains `mics`), VR2b, SW2b, CJ3; VR-S3.
  **Lane** C.
- **Question for the owner:** match faces to mics automatically with the sheet confirming, or always
  ask? *Recommended: automatically, the sheet confirming.*

### SW6 — a channel as a source

- **What a person gets:** on a recorder's many-channel file, or a wireless kit's two-person stereo
  track, the Source section's Channel picks one microphone. That clip sounds mono, and its waveform,
  loudness and speech are that microphone's alone, so Switch by Speaker can tell two people apart on
  one file.
- **Decisions (draft):**
  - **SW-60 — `source.channel` (format p):** one channel of the clip's stream, read as a MONO
    source, allowed on a stream of two or more channels. Read by SW-S1 (b)'s branch: in the tap's
    head stage when the tap sees every channel unmixed in player and export and a picked channel
    reaches both sides equally; otherwise from a mono 48 kHz copy per (file, stream, channel)
    rendered on the offline queue (`RampAudioRenders`), silent while pending, the export waiting.
  - **SW-61 — A stream of more than two channels with no pick:** if SW-S1 (c) found AVFoundation's
    fold unequal, Frame Job folds every channel to both sides at 1/√N; otherwise AVFoundation's fold
    stands.
  - **SW-62 — AU-34 amended:** "A source reading one channel is mono and ignores `channels`, as a
    mono file does. To hear one person of a two-person stereo file alone and have their speech
    measured alone, choose the Channel; Channels ▸ Left changes only what plays." The cache passes
    read the channel directly (SW-S1 (d)) or the copy.
  - **SW-63 — The Source section's Channel popup** ("All", "1", "2", …) and `set_audio_source`'s
    `channel`.
  - **SW-64 — Channels are checked wherever streams are:** `set_audio_source` refuses a channel at
    or past the stream's `channels` ("media M's audio track 1 has 2 channels; channel must be below
    2, not 2"); `validate` refuses a stored one; `relink_media` refuses a file whose stream has
    fewer channels than a clip picks ("clip 12 plays channel 3 of audio track 1; the new file's
    track 1 has 2"); `set_media_speech` gains `channel`, and `audio_speech` entries carry it.
- **Core:** `Source::Media.channel`, `set_audio_source`'s `opt("channel", Index)`, the segment's
  `channel`, SW-64's checks (`edit_audio_source.rs`, `edit_relink.rs`, `media_speech.rs`), the
  format bump with `schema_vN.rs`. Tests in `core/tests/audio_source.rs`.
- **Swift:** by SW-S1 (b): the tap branch generalises AU-34's head stage to one channel of N
  (`AudioTapSchedule.swift`, `AudioDSP.swift`'s `channels`), or the copy branch adds an
  `OfflineAudioJob` kind on `RampAudioRenders` waited for by the export
  (`Exporter+RampAudio.swift`); SW-61's fold if needed; the passes read the channel under the `c<c>`
  key; `ClipLoudness`' matrix for a mono source; the Channel popup in `AudioPane+Source.swift`.
- **MCP:** `set_audio_source`'s and `set_media_speech`'s `channel` print from the op table.
- **Docs:** spec §5.2b, §6b, §6c, §7.2, §4.3d; `audio.md` (recorder files, wireless kits); AU-34's
  line; `docs/manual-checks.md` (JOB-54).
- **Acceptance:** a channel source exports that channel alone in both sides; its caches are its own;
  the switch on a two-person stereo file matches the switch on two separate files; the proof
  against Release; `make gate`.
- **Proof** (`audio_channels_proof.py`, Release; F-POLY, F-SPLIT): H1 each of six channels exported
  alone peaks at its own tone 40 dB above the rest, both sides within 0.5 dB, the WAV's also nulling
  against ffmpeg's `pan=mono|c0=cK` dual mono; H2 the channel's speech cache marks only its speech;
  H3 SW2b's S1 run on F-SPLIT gives the same shots as on two separate files; H4 a six-channel stream
  with no pick plays SW-61's fold; H5 while a copy is pending (copy branch) the clip is silent and
  an export waits; H6 channel 2 of a stereo stream refused in SW-64's sentence, and a relink to a
  mono file refused naming the clip.
- **Mutants** (5): the channel ignored (H1); the channel's speech from the mix (H2, H3); the fold's
  gain wrong (H4); the export not waiting (H5); the bound check removed (H6).
- **Manual check:** **JOB-54** — a recorder's multitrack file (RØDECaster, Zoom, MixPre) or a
  wireless kit's split stereo: two channels placed, each person alone, at a sensible level, in both
  ears.
- **Depends on:** SW4b; SW2b (row H3 runs SW2b's S1 on F-SPLIT); SW-S1. **Lane** A.
- **Question for the owner:** the fold for a many-channel track with no pick, if AVFoundation's is
  unequal? *Recommended: Frame Job's equal fold (SW-61).*

### SW9a — the Angle Viewer

- **What a person gets:** View ▸ Angle Viewer shows every angle at the playhead in a grid beside the
  preview, the program's angle outlined. A click switches from the playhead; ⌥-click switches the
  whole shot.
- **Head:** SW-S2 (c) re-run on the owner's files (S-PC1) first.
- **Room first:** The plan's options wrapper goes in `ReelCore+Plan.swift`, its memo a stored
  property of `ReelProject` in `ReelCore.swift` (CJ-8 (l)).
- **Decisions (draft):**
  - **SW-90 — Angles are derived, not stored:** a shot's angles are SW-13's covering tracks; the
    program track is the selected clip's track, else the front track with a media clip at the
    playhead. No format change.
  - **SW-91 — The viewer is a tap on the compositor, through the plan's options export (CJ-8 (h)).**
    `rc_project_composition_plan_opts(p, opts_json)` takes `{"show_tracks": [ids]}` (those tracks'
    video placed even when hidden or switched off); `ReelProject` memoises its plan per handle AND
    options string. Only `Playback` passes the option, only while View ▸ Angle Viewer shows; an
    export, `render_frame`, Save Frame and the scrub player never do, so no output carries a hidden
    angle. Showing or hiding the viewer rebuilds the composition. `RecipeOptions` gains
    `angle_cells` (the angle tracks in cell order): the recipe keeps those layers off the canvas and
    answers each one's source, and the compositor draws each angle's frame into its cell of a grid
    texture handed to the viewer (as `WaveformTaps` are handed frames). One player, so cells are in
    sync with the program by construction. The viewer's shown state is view state (not persisted).
    The live cell count is SW-S2 (c)'s verdict.
  - **SW-92 — A click switches from the playhead:** the program shot under the playhead is cut there
    and the part after it re-picked by SW-14's sequence, one step; ⌥-click switches the whole shot.
- **Core:** `plan.rs` (the `show_tracks` option read by `assign`'s video placement only);
  `recipe_options.rs` (`angle_cells`) and the recipe's cell sources; `ffi_query.rs` (392 of 400: the
  export goes in a new `ffi_plan_opts.rs` if `ffi_query.rs` would pass 400); no format change. Tests
  `core/tests/plan_options.rs`: without the option the plan is byte-identical.
- **FFI:** `rc_project_composition_plan_opts` (Rust, header, `ReelProject.planJSON(options:)`).
- **Swift:** new `AngleViewerTap.swift` (on `Compositor.serve`, as `WaveformTap.swift` is),
  `AngleViewerView.swift`, `EditorViewController+AngleViewer.swift` (installs the panel the way
  `installSeeing` installs Scopes), `Playback+AngleViewer.swift` (the option on rebuild); the View
  item and validator in `AppDelegate+ViewMenu.swift`; `UIMenuTable.swift` and `inventory.json`
  rows.
- **MCP:** a dev tool `angle_viewer` (per cell, the frames delivered while playing; at a paused time
  a PNG of the grid); `switch_angle` gains `at` for the click form.
- **Docs:** spec §4.2 or §3 (the panel), §7.1, §9; `multicam.md`; `menus-and-shortcuts.md` (View ▸
  Angle Viewer); a screen `04d-angle-viewer.md`; root `CLAUDE.md`'s dev tool list;
  `tools/proof/dev_tools.py`'s count (one more, `angle_viewer`); `docs/manual-checks.md` (JOB-56).
- **Acceptance:** the live cells follow SW-S2 (c) and stay in step with the program; no export or
  rendered frame includes a hidden angle; the proof against Release; `make gate`.
- **Proof** (`angle_viewer_proof.py`, Release; F-TURNS, whose cameras carry a 16-block binary frame
  code): V1 each live cell delivers ≥ 98 % of due frames over 60 s; V2 `play_preview` with the
  viewer open stays within SW-S2 (c)'s band; V3 at five paused times each cell's decoded frame code
  equals the frame `render_frame` shows for that angle alone, and its mean absolute difference from
  that render, box-filtered to the cell's size, is at most 3 of 255 per channel; V4 a click switches
  from the playhead, one step; V5 with the viewer shown an export and `render_frame` are
  byte-identical to the same with it hidden; V6 toggling View ▸ Angle Viewer moves no `UserDefaults`
  key.
- **Mutants** (4): hidden angles left out of the plan (V1); a cell one frame off (V3); the click
  switching the whole shot (V4); the option passed to the export's plan (V5).
- **Manual check:** **JOB-56** — a four-angle episode with the viewer open: the cells move with the
  program, and the outline follows the cuts.
- **Depends on:** SW2b; SW-S2 (c). **Lane** C.
- **Questions for the owner:** (1) Angles derived or stored on the program track (`tracks[].angles`,
  a format bump)? *Recommended: derived.* (2) A panel beside the preview, or a window? *Recommended:
  a panel*, like Scopes. (3) A multicam clip with angles inside one clip instead of a program track?
  *Recommended: no* (SW-3).

### SW7b — Detach Audio per track and per channel

- **What a person gets:** Detach Audio on an OBS recording puts the mix, the microphone and the
  desktop on their own clips, grouped with the picture ("Detach Audio Tracks"); Detach Audio
  Channels splits a recorder's file into one clip per microphone.
- **Decisions (draft):** **SW-75 — Detach Audio on a file with several audio tracks makes one sound
  clip per decodable track**, the picture's sound off, all in one group, each on its own new track
  below, one undo step; the item reads "Detach Audio Tracks" there. Clip ▸ Detach Audio Channels
  makes one mono clip per channel of the clip's stream. `detach_audio {clip, per?:
  "track"|"channel"}`; absent is "track", which on a one-track file is today's Detach Audio exactly.
  `per` is a closed vocabulary: `Kind::DetachPer` in `op_table.rs` with its `values()` row and its
  arm in `op_schema.rs`; `core/CLAUDE.md`'s kind count rises by one.
- **Core:** `edit_detach.rs` (100); the kind; `op_rows.rs`' argument. Tests
  `core/tests/detach_per.rs`.
- **Swift:** the item's title by the clip's file and its validator in `clipMenu()`; Detach Audio
  Channels (a new item there); the Mix section's button; `UIMenuTable.swift` and `inventory.json`
  rows for the new item and the retitled one.
- **MCP:** `detach_audio`'s `per` prints from the op table; one sentence of prose.
- **Docs:** spec §6b, §9; `audio.md`, `menus-and-shortcuts.md`; `core/CLAUDE.md`.
- **Acceptance:** one undo step makes one grouped sound clip per track (or channel), each on its
  stream (or channel), in sync; the proof against Release; `make gate`.
- **Proof** (rows in `audio_streams_proof.py`): D1 a three-track file: picture plus three grouped
  sound clips, each identifying as its track; D2 a six-channel file: six mono clips; D3 a one-track
  file: today's Detach Audio, `get_project` identical to the build before; D4 an undecodable track
  skipped.
- **Mutants** (3): every sound clip on stream 0 (D1); the group not formed (D1); `per` absent
  treated as "channel" (D3).
- **Depends on:** SW7a, SW3a, SW6. **Lane** A.
- **Question for the owner:** include track 1 (OBS's mix) when detaching? *Recommended: yes*; the
  person deletes the one they do not want.

### SW9b — switching while playing

- **What a person gets:** with the viewer shown, keys 1–9 or a click while playing cut to that angle
  at that moment; the marks show on the program track, and stopping applies them as one undo step.
- **Decisions (draft):** **SW-95 — Presses are recorded and applied when playback stops:** keys 1–9
  (bare, while the viewer is shown) and clicks while playing are recorded as (time, angle), drawn as
  marks, and applied at stop as one step "Switch Angles" — each press cuts at its frame-snapped time
  and holds that angle to the next press or existing cut; a press within a frame of another replaces
  it; editing while playing never rebuilds the composition. **SW-96 — `switch_angles {track, cuts:
  [{at, angle}]}`** applies the same edit for an agent.
- **Swift:** new `EditorViewController+AngleSwitch.swift` (the recorder and its apply); the
  bare-digit arms in `handleEditorCharacter` (wiring only in the frozen file, below any modified
  case of the same key); new `TimelineView+AnglePresses.swift` (the pending marks).
- **MCP:** `switch_angles` (SW-96).
- **Docs:** spec §9 (keys 1–9; checked for a clash, CJ-8 (e)), §7.9e; `multicam.md`,
  `menus-and-shortcuts.md`; `docs/manual-checks.md` (JOB-57).
- **Acceptance:** presses land on their frame-snapped times as one step; nothing rebuilds while
  playing.
- **Proof:** a probe of the press recorder (replacement within a frame, the hold to the next cut);
  W1 `switch_angles` with five cuts gives five shots and one step; W2 while `play_preview` plays
  with presses recorded, `playback_rebuilds` answers no new entry until playback stops, and exactly
  one after.
- **Mutants** (2): a press applied at once (W2); a press within a frame kept as a second cut
  (probe).
- **Manual check:** **JOB-57** — pressing 1 and 2 as the speakers change: playback never stutters at
  a press, and the cuts land where pressed.
- **Depends on:** SW9a. **Lane** C.
- **Question for the owner:** apply at stop, or edit live? *Recommended: apply at stop.*

### VR7a — linked versions: framings in the model, their ops and carries (asked)

- **The gate:** CJ0a's question 8 (survey decision 5), answered yes, 2026-11-01. VR3's copy ships
  first either way. The vertical trial (VR-38, JOB-35) may withdraw the yes before VR7a starts if it
  finds copies cost nothing to re-make; if it does, VR7a–VR9 are filed as one issue carrying this
  design.
  VR7a–VR9 run in lane B after SW7a (their carries edit the same `edit_link.rs` and
  `edit_clip_timing.rs`), and VR7b waits for lane C's SW9a; the integrator may move them to an idle
  lane once their dependencies have landed. They share VR-70…VR-79 (VR7a, VR7b), VR-80…VR-89 (VR8)
  and VR-90…VR-99 (VR9).
- **Head:** VR-S4 runs; its verdict is recorded as VR-83 before any code.
- **What a person gets:** nothing visible yet. A project can hold a 9:16 framing whose clip
  placements follow every edit of the main cut; agents add one and place clips in it.
- **Toll first:** `ProjectSnapshot.swift`'s `// MARK: - Canvas` (`CanvasSnapshot`, 392–442) →
  `CanvasSnapshot.swift`; then wiring only (G2-2's precedent), the types in `FramingSnapshot.swift`.
- **Decisions (draft):**
  - **VR-70 — A project may hold more than one framing:** `framings: [{id, name, width, height}]`;
    the canvas is the main framing (format p). Amends spec §2's idea 2 ("a fixed canvas per framing:
    the document has a main size and, since VR-70, other framings of the same cut").
  - **VR-71 — A clip's placement in a framing is its own list:** `Clip.framed: {<framing id>: {x, y,
    scale, actions: [Action]}}`, a similarity from the main canvas to that framing over time; its
    actions name only x, y and scale, follow §5.4 among themselves and never meet the clip's own
    list; a clip with no entry is placed by `keep`. Amends §5.4 ("Video, audio and text properties
    all go through the one list, except a clip's placement in another framing, which is its own
    list").
  - **VR-72 — In framing v a layer is placed at F_v(t) ∘ placement(t)**, F_v the planner's framing
    path stored rather than composed (exact where VR-27 approximates); nest clips carry framings,
    clips inside a nest do not.
  - **VR-73 — A track may belong to one framing** (`tracks[].framing`, an id or `"main"`, written
    only when set): a framing's captions, re-sized graphics and backdrops live on its own tracks,
    the main's on tracks marked `main`; picture edits on shared tracks reach every framing.
  - **VR-75 — The carries:** every op that splits, trims, re-times, re-snaps or copies a clip's
    actions does the same to its framing lists through the same helpers; a blurred copy drops them;
    a link group (SW-70) carries nothing of its own, each member's list being its own.
  - **VR-76 — The ops:** `add_framing {name, width, height}` (even sizes, `set_canvas`'s bounds),
    `set_framing {framing, name?, width?, height?}`, `remove_framing {framing, with_tracks?}`
    (removes every clip's entry; refused while a track belongs to the framing unless `with_tracks`,
    naming the tracks), `set_clip_framing {clip, framing, x?, y?, scale?}`, and an optional
    `framing` on `add_action`, `set_action`, `set_action_end` and `remove_action` (an end in a
    framing names only `video.x`, `video.y` and `video.scale`, else refused by name). The four new
    ops are document-level: they join `scope.rs`'s `refused_inside` and `ReelOp.documentLevelNames`,
    because clips inside a nest carry no framing (VR-72); the action ops' `framing` is refused in a
    scope by name.
- **Core:** the fields behind the bump with `schema_vN.rs`, types in new `model_framing.rs`; new
  `framing.rs` (evaluation, reusing `actions.rs`' curve reading); new `edit_framing.rs`;
  `op_rows.rs`, `edit.rs`, `scope.rs`; the carries in `edit_split.rs`, `edit_clip_timing.rs` (after
  SW7a's toll), `edit_speed_profile.rs`, `edit_link.rs`, `edit_paste.rs`, `edit_nest.rs`,
  `frame_grid.rs`, `time_bounds.rs`, `edit_background.rs`; `edit_action.rs`'s `framing` arm through
  `edit_action_end.rs`. Tests `core/tests/framing.rs` (each op and refusal; each carry against an
  oracle that splits, trims, re-times and pastes the framing list as the clip's own; an old project
  read and written with no `framings` key).
- **Swift:** `ProjectSnapshot.swift` wiring; `FramingSnapshot.swift`; `ReelOps` builders and
  `documentLevelNames`; `TrackSnapshot.framing`.
- **MCP mirror:** the four op tools printed from the op table, their catalog rows in
  `AgentCatalog+Framing.swift` declaring `scope`; the action tools' `framing` printed from the
  table; `get_project` shows `framings`, `framed` and `tracks[].framing`; the CJ-8 (g) counts (four
  ops, four tools, `documentLevelNames` four more, `scope.rs:172`'s figure, §6a's count).
- **Docs:** spec §5.2, §5.4's note, §6c, §6a, §2's note; `core/CLAUDE.md` (`model_framing.rs`,
  `framing.rs`, `edit_framing.rs`); `app/CLAUDE.md` (`FramingSnapshot.swift`,
  `CanvasSnapshot.swift`); `vertical-and-framing.md` (framings, for agents).
- **Acceptance:** core tests; the proof against Release; `make gate`.
- **Proof** (`vr7a_proof.py`, Release): F1 `add_framing` then `set_clip_framing` read back through
  `get_project`; F2 a split carries both halves' framing lists, the second half's rebased as its
  actions are; F3 a trim, a speed change, a ramp's rate edit and a paste each carry; F4 an older
  project opens unchanged and saves with no `framings` key; F5 `remove_framing` with a framing-only
  track refused naming it, and with `with_tracks` removes the track and every entry as one step; F6
  an action added with `framing` never overlaps-checks against the clip's own list, and an end
  naming `video.opacity` in a framing is refused; F7 `set_clip_framing` in a nest scope refused in
  `refused_inside`'s sentence.
- **Mutants** (7): the split not carrying the list (F2); `trim_start` not rebasing the list (F3);
  `set_speed` not scaling it (F3); paste dropping it (F3); `remove_framing` leaving entries (F5);
  the framing list checked against the clip's own (F6); a non-placement key accepted in a framing
  end (F6).
- **Manual checks:** none. **Depends on:** CJ0a's question 8 answered yes, VR4, SW7a; VR-S4.
  **Lane** B.
- **Fallback split** (if the design pass finds it more than one pipeline): VR7a1 the model, the four
  ops, the action ops' `framing` and evaluation (F1, F4–F7); VR7a2 the carries (F2, F3).

### VR7b — linked versions: the recipe, the plan and export per framing (asked)

- **What a person gets:** Export can write any framing: the Export sheet gains a Framing row when
  the project has one, and the Export Queue's row names the framing.
- **Decisions (draft):**
  - **VR-74 — Preview and export pick a framing:** `RecipeOptions.framing` through
    `rc_project_frame_recipe_opts`' existing options JSON (header :428); the plan's options export
    (CJ-8 (h), built by SW9a) gains `framing` and its track filter (VR-73: a framing's tracks and
    the shared ones, never another framing's or the main's); an export override `framing` read by
    `export_overrides.rs`, so the resolved settings take the framing's size (an unknown id refused
    by name).
  - **VR-77 — The Export sheet's Framing row** (Main, then each framing by name) shows only when the
    project has framings, is remembered per document as the sheet's other rows are, and its choice
    is the export's `framing`; the default file name gains " (9:16)" for a framing named "9:16";
    `render_frame {framing}` draws one frame of it.
- **Core:** the recipe's placement through F_v (VR-72), one call in `recipe.rs`;
  `recipe_options.rs`; `plan.rs` (the track filter); `export_overrides.rs` and `export.rs` (the
  framing's size). Tests `core/tests/framing_render.rs` (the main's recipe and plan byte-identical
  with and without framings; a framing's layer placement equal to F_v ∘ placement at sampled ticks;
  the track filter).
- **FFI:** none new: SW9a's options export takes the key (CJ-8 (h)).
- **Swift:** `ExportSheetFraming.swift` (the row, after Size), `ExportSheetController.swift` wiring;
  `Exporter` passes `framing` to the recipe option and the plan options; `ExportQueueController`'s
  row text; `AgentServer+Render.swift` (`render_frame`'s `framing`).
- **MCP mirror:** `export`'s `framing` override (the export tool's prose); `render_frame`'s
  `framing`.
- **Docs:** spec §7.1, §7.2, §7.3, §7.8, §7.9a; `export.md`, `vertical-and-framing.md`;
  `core/CLAUDE.md` (`recipe_options.rs`, `export_overrides.rs`).
- **Acceptance:** core tests; the proof against Release; `make gate`.
- **Proof** (`vr7b_proof.py`, Release): 1 on a fixture where no framing move falls inside an
  existing action, a framing's export equals the VR3 copy's export of the same cut, byte for byte at
  sampled frames; 2 on VR3's fixture, the frames inside its one such action are excluded and
  counted, every other sampled frame byte-identical; 3 the main framing's plan and export
  byte-identical to before; 4 the export of a 9:16 framing is 1080 × 1920 and an unknown `framing`
  is refused by name; 5 the sheet's Framing row (a probe of `ExportSheetController` over a project
  with one framing) sends the override, and the queue row names it; 6 `render_frame {framing}`
  equals the export's frame at the same time.
- **Mutants** (5): the framing option ignored by export (1); the track filter off (2); the plan
  option ignored by the preview (6); the export's size from the main canvas (4); the sheet's row not
  passed (5).
- **Manual checks:** none. **Depends on:** VR7a, SW9a. **Lane** B.

### VR8 — linked versions: preview and canvas editing per framing (asked)

- **What a person gets:** a Framing popup beside the preview picks the main framing or 9:16; in 9:16
  the canvas handles move and scale the clip's framing, not its placement, the Transform section
  edits the framing, and the action lane shows the framing list.
- **Toll first:** `CanvasSessions.swift` (1,081, over the cap, no named seam until now) gives up
  `// MARK: - Region drags` (891–1064) → `CanvasRegionDrag.swift`, a pure move gated alone, its new
  "Named next cuts" entry written. `PreviewCanvasView.swift` (frozen, 1,121) and
  `EditorViewController.swift` (frozen) take wiring only.
- **Decisions (draft):**
  - **VR-80 — The Framing popup and View ▸ Framing ▸.** The toolbar's view group gains a Framing
    popup (Main, then each framing by name), shown only when the project has framings; View ▸
    Framing ▸ lists the same items (filled on open, as `LookMenuFiller` fills Look). The shown
    framing is view state, kept per window in one stored property of the frozen
    `EditorViewController.swift` (wiring), never persisted and never written to `UserDefaults`, so a
    proof may perform the menu item. A removed framing falls back to Main.
  - **VR-81 — Editing in a framing.** `CanvasEditTarget` gains a third target, the shown framing
    (with the selected action of its list, CI-13's rule applied to that list): the move and scale
    sessions write `set_clip_framing {x, y, scale}` or `set_action_end {framing, patch}`; rotate,
    crop, shape endpoints, regions and the obscure grips are not offered in a framing. The
    Transform section's X, Y and Scale read and write the framing; every other row of the Picture
    sub-tab is ⊘ with the note "Set in Main". The action lane and the timeline's action bands show
    the framing list; adding an action there (⌥⌘K) adds it to the framing list.
  - **VR-82 — A clip with no entry in a framing is placed by `keep`** (VR-71) until the person
    frames it: the popup's menu shows "N clips not framed" and Clip ▸ Follow Subject… with the
    framing shown frames the selected ones into its list (VR-90). Nothing is analysed or edited
    behind the person's back. (The alternative, framing a new clip automatically once its analysis
    lands, as AU-68's follow-ups do, is the owner's question.)
  - **VR-83 — The preview's rebuild rule, VR-S4's verdict:** under 1 s on the owner's Mac the
    preview rebuilds on a switch; otherwise `Playback` keeps the last two framings' compositions and
    swaps them.
- **Swift:** new `EditorViewController+Framing.swift` (the popup, the View items and their validator
  arm, the shown framing's setter); the frozen `EditorViewController.swift`'s one stored property;
  new `Playback+Framing.swift` (the recipe option and plan option on rebuild, VR-83);
  `CanvasEditTarget.swift` (the framing target); `CanvasSessions.swift` after its toll (the move and
  scale sessions through the target); the frozen `PreviewCanvasView.swift`'s wiring (the shown
  framing's canvas size for `viewToCanvas`, and the handle set's one guard); `VideoPane+Transform`
  and `InspectorBinding` (the framing reads and writes, the ⊘ rows); `ActionLaneView.swift`,
  `TimelineActionBands.swift` (the list shown); `AppDelegate+ViewMenu.swift`; `UIMenuTable.swift`
  and `inventory.json` rows.
- **MCP mirror:** the edits are VR7a's ops; `render_frame {framing}` (VR7b) draws the shown framing;
  `snapshot_ui` reports the shown framing.
- **Docs:** `vertical-and-framing.md` (editing per framing), `menus-and-shortcuts.md` (View ▸
  Framing ▸); spec §3, §4.2, §4.3b (Transform in a framing), §9; `app/CLAUDE.md` (the third edit
  target, the new files, the toll); a screen `18c-framing-popup.md` (provisional);
  `docs/manual-checks.md` (JOB-38).
- **Acceptance:** the probe and the proof against Release; the screen captured; `make gate`.
- **Proof** (`vr8_probe.swift` through `swift_build.py`, and `vr8_proof.py`, Release): P1 View ▸
  Framing ▸ 9:16 by `perform_menu_item` makes `snapshot_ui` report a 1080 × 1920 canvas and the
  window's recipe key carries the framing; P2 (probe) with the framing shown, the move session's ops
  are `set_clip_framing {x, y}` and never `set_video`, and with a framing action selected
  `set_action_end {framing, patch}`; P3 (probe) the rotate and crop handles are absent and the
  Transform section's Rotation row is ⊘ in a framing; P4 the action lane's layout dump lists the
  framing list's actions; P5 switching framings adds one entry to `playback_rebuilds` under VR-83's
  rebuild branch and none under its keep branch on the second switch back; P6 the switch moves no
  `UserDefaults` key; P7 an edit made in 9:16 leaves Main's `render_frame` byte-identical.
- **Mutants** (5): the move session writing `set_video` in a framing (P2); the rotate handle live in
  a framing (P3); the lane showing the clip's own list (P4); the keep branch rebuilding (P5); a
  framing edit reaching the main placement (P7).
- **Manual check:** **JOB-38** — switching and editing per framing: the popup, a drag, a scale and
  an added action in 9:16 behave as in Main, and Main is untouched.
- **Depends on:** VR7b. **Lane** B.
- **Questions for the owner:** (1) The popup in the toolbar's view group, and View ▸ Framing ▸?
  *Recommended: yes.* (2) Only X, Y and Scale editable in a framing? *Recommended: yes* (VR-71's
  similarity). (3) A clip added after the framing: `keep` until framed by Follow Subject, or framed
  automatically once its analysis lands? *Recommended: `keep` until framed* (no edit made behind
  the person's back).

### VR9 — Make Vertical Version writes a linked framing (asked)

- **What a person gets:** the sheet's "Make a Copy" becomes a choice of "Add to This Project"
  (linked, the default once this lands) or "Make a Copy". Added to the project, the 9:16 framing
  follows every later edit of the main cut and exports from the same document.
- **Decisions (draft):**
  - **VR-90 — `reframe_clip {framing}` writes the path into the framing list, composing nothing.**
    With `framing`, the planner's path F is stored as the clip's `framed[framing]` base and actions
    (VR-72) instead of being composed into the clip's own base and actions; VR-27's approximations
    do not arise (no move is carried by an existing action, nothing is re-eased), so the summary's
    re-eased and approximate counts are 0. A clip's existing framing list is replaced.
  - **VR-91 — Captions and re-laid graphics go on framing-only tracks.** The main's caption tracks
    are marked `framing: "main"` and VR4's re-paged pages go on new tracks of the framing; a graphic
    the old canvas's size (VR-42) moves to a new main-only track and its re-sized copy goes on a
    framing-only track (one `move_clip` and one copy each, counted); the main's export is unchanged.
  - **VR-92 — Backdrops on a framing-only track** ("Backgrounds (9:16)").
  - **VR-93 — `make_vertical_version {link: true}`** applies the step to the addressed project as
    one undo step "Add Vertical Framing" (an `add_framing`, then VR-33's classes written into the
    framing); `path` and `copy` are refused with `link`.
  - **VR-94 — A layout role in a linked framing takes the framing's `keep`.** A framing list holds
    only x, y and scale (VR-71), so CO's layouts, which write crop, radius and opacity, cannot be
    re-solved there; the sheet says "Camera layouts re-lay only in a copy" and offers Make a Copy
    when the project has layout switches, and the summary lists the roles.
- **Core:** `edit_reframe.rs` (`framing`); `op_rows.rs` (`reframe_clip` gains `opt("framing",
  Id)`). Tests in `core/tests/reframe.rs` (a framing list equal to the path; the clip's own list
  untouched).
- **Swift:** `VerticalVersion.swift` (the linked mode: VR-91, VR-92, VR-94, one grouped edit);
  `VerticalVersionSheetController.swift` (the choice; the note); `AgentServer+VerticalVersion.swift`
  (`link`).
- **MCP mirror:** `make_vertical_version`'s `link`; `reframe_clip`'s `framing` printed from the op
  table.
- **Docs:** `vertical-and-framing.md` (linked versions: what follows the main, what does not); spec
  §6c, §7.9e; `docs/manual-checks.md` (JOB-30).
- **Acceptance:** the proof against Release; `make gate`.
- **Proof** (`vr9_proof.py`, Release): L1 the linked framing's export equals the VR3 copy's frame
  for frame on the fixture, outside the frames VR7b's row 2 counts; L2 a trim and a ripple delete in
  the main after linking show in the 9:16 export with no re-making; L3 the main's export
  byte-identical before and after linking; L4 one undo restores `get_project`; L5 the main's caption
  pages unchanged and the framing's re-paged within VR4's measure; L6 `link: true` with `path`
  refused; L7 a project with a layout switch: the sheet's note shows and the roles are listed.
- **Mutants** (4): composition into the clip's own actions with `link` (L3); captions on shared
  tracks (L5); the main's graphic left on a shared track (L3); `path` accepted with `link` (L6).
- **Manual check:** **JOB-30** — the owner edits a main cut after adding its 9:16 framing, exports
  both, and the vertical follows without re-making.
- **Depends on:** VR8, VR5b. **Lane** B.
- **Question for the owner:** the sheet's default once VR9 lands? *Recommended: Add to This Project*
  (it follows later edits; a copy is one click away).

### The owner's trials

Each trial is a one-off judgment, recorded here and as a verdict under its decision ("**Verdict
(owner, date):** …", GR-1's form), never only in a reply; a repeatable check it leaves becomes a JOB
row citing its source. Each finding becomes a phase, an amendment or an issue.

- **CJ-5, the lead segment (T1 talking head from S-TH1, T2 screen tutorial from S-ST1).**
  - *Baseline*, when TX1 starts, in that day's build: both cut to a state the owner would publish.
  - *Checkpoint CP1*, after TX3: T1 again, read and cut by deleting words in the Transcript tab.
  - *Closing run* TX8, when TX7 lands: both again, with TX's figures.
  - Recorded per video and run: the source and its length; every point where the owner left Frame
    Job for another tool or gave up, with the tool and the reason; each step that took noticeably
    longer than it should; which bet would have changed it; at CP1, each word cut that sounded wrong
    with its time; at TX8, `transcript_verdict.py`'s figures. The verdict goes under CJ-5; TX-80
    points to it.
- **CU12, screen tutorials with CU's tools:** one real 10–20 min narrated tutorial with Record
  shortcuts on and a camera beside, against T2's baseline; time spent, what was redone by hand, the
  items to change (CU-120…; JOB-25's zoom verdict carried in).
- **VR-38, vertical versions (JOB-35):** T1's and T2's vertical versions watched on a phone; whether
  the framing, the whole-shot treatment and the captions were what the owner would post, and whether
  re-making copies after master edits was a cost (a no may withdraw CJ0a's question 8's yes before
  VR7a starts).
- **FC-91, shorts (JOB-44):** Find Clips on one real long recording (S-PC1 or S-LONG1; a guest's
  only with their agreement), ten shorts made and watched on a phone; whether the picks were the
  moments the owner would have chosen, whether the reasons were true, what the run cost.
- **SW-29, podcasts (JOB-51):** one real episode (S-PC1) through Synchronize Audio and Switch by
  Speaker with the defaults, watched through.
- **CO's verdicts:** JOB-60 (edges on S-TH1, S-TH2, S-TH5; decides whether a matting-model candidate
  is filed), JOB-62 (Text Behind Subject), JOB-63 and JOB-64 (layouts and hide-while-silent on
  S-ST1), each written into its phase's record.

### Closing the road map

When the last phase built has landed (VR7a–VR9 included only if the owner said yes):

- **ADR.** Condense this file into `designs/adr/creator-jobs.md` (an existing ADR, such as
  `designs/adr/audio.md`, is the template): what was built per bet, the spikes' verdicts, the
  trials' verdicts, the decisions by ID, the deviations, and "Where to look in the original".
- **Archive.** `git mv designs/creator-jobs.md archive/` and `git mv designs/creator-survey.md
  archive/`, each with its row in `archive/INDEX.md`; the root `CLAUDE.md`'s ADR table gains the
  `creator-jobs` row (the six bets, the key rule, the analysis lane, and where each is recorded).
- **Issues.** Every unfinished item — each phase's residue, a skipped real-sample row still owed,
  each candidate named in "Not in this road map" that the phases left out, a spike's filed
  alternative (CO-S3's better refinement, CU-S1's A10 replacement, a Performance shortfall from
  SW-S2 or SW1's P5, V8's Remove Struck timing) — is reviewed against the tree and filed with
  `ai-drafted` and `low-priority` (unless urgent by the repo's rule), performance items in the
  "Frame Job — Performance" project.
- **Guide and README.** Every user-visible change has its page in `docs/guide/` (new:
  `transcript.md`, `vertical-and-framing.md`, `find-clips.md`, `multicam.md`), its
  `menus-and-shortcuts.md` rows and its README highlight; a final read checks each claim against the
  code.
- **Manual checks.** `docs/manual-checks.md` holds JOB-1…JOB-65's rows that survived (renumbered
  inside their blocks); the owner runs the list.
- **Maps and counts.** The three `CLAUDE.md` maps, `app-file-history.md` and `core-file-history.md`
  ("Named next cuts") and every pinned count are current.
- **Rasterize.** FC5's `agent/` diff is applied there (its issue closed) or the root `CLAUDE.md`'s
  `agent/` line says how the two differ.

## Samples the owner supplies

The owner's cameras are a LUMIX GH5 and an iPhone 18 Pro; the microphone is the RØDE USB of
`samples/Rode-usb-mic.m4a`. Every sample lives in `tools/proof/media/creator/` (gitignored), with a
row in `samples/README.md`, and is never committed (it carries the owner's face and voice). No phase
waits for one: a row that needs a missing sample skips by name and is owed in the phase's record. A
spike that sends a sample to a cloud service sends only the owner's own speech, and a guest's only
with the guest's agreement, recorded in the spike's README.

| Sample | What to record | First needed by | What it measures |
|---|---|---|---|
| S-TH1 | A talking head, one person, GH5 in its standard (Rec. 709) profile, 4K 30, about 6 min, the RØDE recorded as its own file beside the camera's sound. The first 60 s face the camera. Three lines said twice (retakes), two false starts, natural fillers, one 3 s pause; once leaning out of frame, once standing up and leaving for about 3 s, about 5 s turned away and a side-on beat, with the times written down. | TX1 (TX-S1; the CJ-5 baseline T1) | Trial T1; real cut edges (TX-S3), retakes (JOB-14) and the same-speech note (with the RØDE file); JOB-10…JOB-13; face share, recall and mouth opening (CJ-S2, CJ3 F5); a no-cut input (CJ-S4); people and framing (VR-S1, VR-S2, JOB-31); mask speed and edges (CO-S1, JOB-60, JOB-62); speech-only input, sentence ends and tokens (FC-S1, FC-S2, FC-S3) |
| S-TH2 | The same set-up on the GH5 in V-Log L, 4K 25 10-bit, about 2 min. | CJ3 (CJ-S2 rule 5) | Faces and masks on log footage, raw against converted (CJ-S2, CO1 M4, JOB-60) |
| S-TH3 | 1 min on the iPhone 18 Pro in Apple Log. | CJ3 | The Apple Log arm (CJ-S2 rule 5) |
| S-TH4 | The iPhone 18 Pro at its default settings (HDR, HLG, variable frame rate): 1 min landscape and 20 s portrait, one person. (VR's S-VR1 is this.) | CJ2a (CJ-S3) | The HLG arm, rotation and a VFR file (CJ-S2, CJ-S3, VR-S1 rule 5, VR1 row 10, CO-S2 (1)) |
| S-TH5 | 1 min of hard cases: backlit by a window, hair against a busy background, turned away, small in frame. | CO4 | Where person segmentation fails (JOB-60) |
| S-KEY1 | Either camera, 1080p30, the owner before an evenly lit green or blue cloth (or any saturated plain colour unlike skin and clothes): 15 s still, 20 s gesturing, 15 s turning the head with hair visible, 10 s leaning out of frame. | CO0 (CO-S1, CO-S3) | Ground truth for masks: Frame Job's own chroma key makes a reference alpha; the keyed person over a screen recording, a photo under a slow pan and a dark wall gives three clips with exact truth for J and B, and one re-tagged with a 90° rotation gives portrait truth (CO-S1, CO-S3, CO4) |
| S-RT1 | The retake script in `tools/proof/retake_spike/SCRIPT.md`, read on the RØDE, 3–5 min; audio alone is enough. | TX3 (TX-S3), TX7 (TX-S4) | The retake rule's answer key on real speech; cut boundaries in a known word order |
| S-ST1 | A screen tutorial with the camera beside it, made with today's recorder: clicks, typing, two shortcuts, scrolling, natural mistakes, 5–8 min. | TX1 (the CJ-5 baseline T2) | Trial T2; three tracks cut together and the clip count after a full edit; stray system-audio words; layouts and hide-while-silent (JOB-63, JOB-64); the `fit` treatment of a screen in a vertical version |
| S-ST2 | After CU1b: a narrated screen tutorial, 10–20 min, Cursor In the picture (so the file and the burned pointer can be compared). | CU1b | The cursor file on real use (K1, K2), Auto Zoom on real clicks (CU7), speech against typing (CU9b), cursor-led reframing (VR5, JOB-36) |
| S-ST3 | After CU6: the same kind of recording with Record shortcuts on. | CU6 | Real shortcut capture, overlays (CU8), typing stretches (CU9b) |
| S-ST4 | A window recording whose window is dragged and resized while recording. | CU3c | The window mapping on real use (JOB-27) |
| S-ST5 | If a second display is attached: a recording of one display while the pointer visits the other. | CU3c | Off-display positions (JOB-28) |
| CU12's recording | A real narrated tutorial, 10–20 min, Record shortcuts on, a camera beside. | CU12 | The screen-tutorial trial |
| S-PC1 | Two people, two cameras (GH5 on one, iPhone on the other) and a wide if a third camera is to hand; a microphone each, and each also wearing a lavalier recording at the same time if two are to hand; 15–20 min with crosstalk and laughter. With it, `turns.json`: turn markers over a five-minute excerpt, drafted from the lavaliers by an agent with `add_marker`, corrected by the owner, read back through `get_project`. | SW2a (SW-S4) | Switching and mic bleed (SW-S4, JOB-51, SW-29), real codecs (SW-S2 re-run at SW9a), a derived-document carry on several media (CJ5b D9), real laughter and the shorts trial (FC-44, with the guest's agreement) |
| S-PC2 | Two people sharing ONE microphone, a camera on each person, each also wearing a lavalier, 5–10 min, with its `turns.json`. | SW8 (SW-S3) | The one-microphone mode from mouth opening (SW-S3, JOB-55) |
| S-PC3 | Two people in ONE wide shot (one camera framing both), a microphone each, 3–5 min. | VR2b (JOB-32) | The two-shot rules (VR-24, JOB-32), face-to-mic agreement (VR-S3, VR6, JOB-37), two-person masks (CO, optional) |
| S-MT1 | An OBS screen recording with the mix on track 1, a microphone on track 2 and the desktop on track 3, once as `.mkv` and once as Hybrid MP4. | SW3a (SW-S1 (f)) | Every audio track of a file (SW3a, SW5, JOB-53) |
| S-MT2 | A recorder's or mixer's multichannel file (RØDECaster Pro II, Zoom F- or H-series multitrack, MixPre), or a wireless kit recording two people into one stereo track. | SW6 | A channel as a source (SW6, JOB-54) |
| S-IP1 | A short iPhone 18 Pro clip with Spatial Audio on. | SW3a (SW-S1 (f)) | How many audio tracks the phone writes, their channels, whether each decodes |
| S-EV | About 8 min: the owner talking to camera while a second person off-mic laughs (chuckles, full laughs, long laughs), claps (single claps and short runs) and cheers, at least 20 times each, with a written list of each event's start to the second. | FC3 (FC-S1) | Sound Analysis recall per group with at least 10 held-out events each (FC-30) |
| S-MU | 2 min of the owner talking over a music bed. | FC3 (FC-S1) | Music confusion and the weak groups' note |
| S-LONG1 | A recording of an hour or more (S-PC1 extended, or any long talk). | TX1 (TX-S1, optional) | The whole-file fill on real material (TX-S1), a real transcript against FC-62's limit and the trial's cost, multi-hour seeking (SW-S2 (d)) |
| T1's and T2's exports | Each trial project's 16:9 export, re-imported as one flattened clip beside the project. | CJ2a (CJ-S4) | Hard cuts in a real flattened edit (CJ-S4), vertical versions end to end (VR3, VR4, VR-S2, JOB-35) |

**Already here:** `samples/Rode-usb-mic.m4a` (30 s, clean but quiet; cut edges on a quiet recording;
FC-S1's speech-only input) and `tools/proof/media/filler-sample/test-recording.aifc` (the owner's
o2, 29.4 s, eight fillers; TX-S3, and TX6's fillers with a fake AssemblyAI answer).

**Synthetic, made by the proofs** (agent-made with `ffmpeg` and `say` into `tools/proof/work/`,
never committed; their lines in `tools/proof/README.md`):

- **Shots:** `testsrc`, `testsrc2`, a green card and a hue-shifted `testsrc` joined at known frames,
  one `xfade` dissolve and one single white frame; a 40-clip fixture project exported by Frame Job
  as a flattened clip, its cut list from `get_project` (CJ-S4, CJ2a, CJ2b).
- **Faces:** frames from `/System/Library/Photos/Resources/FlexAudio/` (the album covers macOS
  ships), read in place at proof time, each source's SHA-256 recorded and a missing one a scored
  failure naming its path: the moving still (a frontal face moved across 1920 × 1080 at a known
  speed), the small face (an eighth of the frame's height), the two-face fixture (the two-person
  cover, then one face leaving) and a portrait-rotated copy (CJ-S2, CJ3, VR1); the moving still with
  a Camera Log set (the converting fixture).
- **Canned analyses** (CJ-26): `faces` and `subjects` with known motion — a face panned for 20 s,
  leaving for 2 s and returning, two faces 400 px then 1,400 px apart, a still face, known cuts, a
  no-subject screen (VR2a–VR6, SW8); `masks` packs carrying CO-S2's bar code (CO2a–CO5).
- **Masks:** a moving disc as a mask sequence; CO-S2's bar-code movie; the E9 fixtures
  (`vision_fixtures.sh`, the slow push-in, the no-person UI scroll, a rotation-tagged push-in);
  Apple Log, HLG and HLG VFR `ffmpeg` fixtures.
- **Cursor:** hand-written cursor files in `core/tests/fixtures/cursor/` (paths, clicks in visits,
  scroll bursts, shortcuts, repeats and near pairs, typing around shortcuts, hidden spans, a newer
  version, a malformed file per refusal); a one-hour synthetic file (CU-S4); `land_recording`'s
  fixture — a `testsrc2` movie at 2880×1800, 60 fps, no cursor, with its cursor file and a 48 kHz
  speech microphone, and a twin with the sprite burned in at the file's positions (L8).
- **Words:** `say` phrases joined by known silences (TX-S3, TX3, TX6); 10 and 60 minutes of joined
  `say` speech (TX-S1); S-RT1's script read by `say` (TX-S4, TX7); a 27,000-word transcript injected
  as a device cache (TX-S2, TX2a); `say` speech with known sentences, gaps, two voices on two tracks
  and one voice duplicated on two tracks (FC4); public-domain texts as timed transcripts (FC-S2).
- **Stand-ins:** `assemblyai_fake.py` (punctuation, speakers, disfluencies, both `remote_deleted`
  values) and `anthropic_fake.py` (scripted submissions, a refusal, a hostile title, a chosen or
  failing model window); key states — an empty and a dummy-key `-RCSecretFolder` (CJ1, TX6, TX7,
  FC7a, FC7b).
- **Audio streams:** F-TURNS (Samantha and Daniel on a scripted turn table, solo stems and measured
  onsets, bleed at −12/−18/−24 dB and pink noise at −55/−45 dBFS, three 1080p colour-card cameras
  with a 16-block binary frame code, one camera as two abutting files); F-MULTITRACK (MOV, MP4 and
  MKV with three audio tracks of distinct tones and speech placements, 48 kHz LPCM, 44.1 kHz, one
  undecodable); F-POLY (a 6-channel 48 kHz 24-bit WAV with and without a layout, and a 6-channel
  AAC); F-SPLIT (one voice per side with bleed); F-4K (about 34 GB, only behind `--build-4k`).
- **Projects built over MCP:** a duplicated track, a nest, a nest shown twice and one trimmed short,
  a transition, a locked track, a ramp, a reversed clip, a detached pair, a music bed and a caption
  clip across a cut, a project one cut short of `RC_MAX_CLIPS`, generated packages of N clips
  (CJ-S1).

**How Vision-dependent proofs stay deterministic:** (1) a planner's rows run on canned analyses and
assert bytes; (2) Vision's rows on fixtures and samples assert tolerances fixed before the run,
never exact numbers; (3) a determinism row compares two runs on the pinned device byte for byte; (4)
a proof compares against the cache, never a recomputation; (5) every stamp and results file carries
the OS build, the compute device and the reader's input; (6) stored values depend on one grid point,
so an answer never depends on call order (CJ2a's A9); (7) what only a person can judge — whether a
reframe, a cutout or a switch looks right on real footage — is a JOB row.

## Risks

- **Vision moves under the app.** An OS update or another compute device changes Vision's answers;
  the stamp makes that a re-analysis rather than a mix, a request revision is a kind-version bump,
  and proofs read caches. The fixture faces ship with macOS and could change; their hashes fail by
  name.
- **Analysis competes with playback, export and `AUSoundIsolation`'s renders.** The picture queue
  runs at width 1 and `.utility` until CJ-S3 earns more, and pauses while playing if CJ-S3 (b) fails
  for any kind; an export waiting on masks is slower, accepted.
- **Real speech defeats word timing.** On-device ranges tile the audio and start 270 ms early, and
  continuous speech has no non-speech to cut in; TX-S3 decides the edge rule and JOB-11 judges it, a
  fragment of a deleted word can remain, and on-device sentence ends may fail FC-S3 (then edges come
  from pauses and are labelled approximate).
- **The first fill and the first analysis take minutes.** A multi-hour, multi-microphone project is
  read whole once per media (TX-12), a long file barely used is read whole, a macOS update re-runs
  every fill, and `find_clips` and `get_timeline_transcript` hold the agent lane meanwhile (AI-2);
  masks of an hour of camera may be an hour of background work (CO-S1).
- **The clip ceiling and undo memory.** Every word cut adds a clip per unlocked track; a long show
  switched every few seconds approaches 4,096; each edit keeps a whole project handle. TX and SW
  count against `RC_MAX_CLIPS` and refuse first; CJ-S1 measures whether the ceiling can rise. Remove
  Struck of hundreds of ranges may be slow (V8 records it; a slow figure is filed, not fixed).
- **What restore cannot bring back.** Only material where one file's clip meets itself across a cut:
  a title or caption page wholly inside the cut is gone, a ramped clip's cut is not a cut, halves
  are never re-merged; undo is the exact path.
- **Retake and auto-cut distrust.** Deliberate repetition is struck (every strike is reviewed,
  TX-S4's traps bound it); generated zooms, framings and switches are subjective (survey D16, D17).
  Every result is ordinary edits the person can change, Replace is off by default, and the trials
  set the defaults.
- **Ranking quality is the whole of Find Clips**, and prompt changes after FC9's trial cost paid
  runs. Sound Analysis may be weak on real podcasts and music beds (FC-30 can demote a group to
  weak); a classifier refusal ends a run with its cost; an eight-hour VOD passes FC-62's limit and
  is refused.
- **Text leaves the Mac at Rank** (and only then), and a guest's recording may still need the
  guest's consent; the window and the guide say so.
- **The key rule may surprise.** With neither a key nor a cached transcript, Remove Filler Words is
  greyed where a sheet once explained itself; a disabled keyed menu item carries a title suffix
  naming the key beside its tooltip, because macOS may not show a disabled menu item's tooltip
  (JOB-1 looks).
- **Input Monitoring and key data.** The grant is attributed to the terminal for a shell launch and
  may need a relaunch (CU-S1, JOB-23); the request may not list the app in the pane at all (a report
  on macOS 15; CU-S1's A11 picks between the CoreGraphics and IOKit calls, and the panel's note says
  how to add Frame Job by hand if neither lists it); keystroke times leak from a password field that
  does not enable secure input (no character is stored; JOB-24 shows it); an ad-hoc build loses the
  grant at every `make app`, so granted proof tiers skip by name and every mutant has an ungranted
  killer.
- **`NSCursor.currentSystem` will answer nil in a future macOS.** A nil is checked per sample and
  the arrow drawn; CU-S1 measures a replacement, built only if needed.
- **A lost cursor file leaves a Separate recording with no pointer.** Consolidate, Relink, the Media
  tab, `cursor_warnings` and In the picture mitigate it. E1's fallback timing (off by up to about 22
  ms, CAM-9 (3)) is used for still-start Separate segments; window occlusion is not sampled; hidden
  cursors may not be detectable.
- **Mask edges, misses and size.** Vision's 512×384 masks may look cut with scissors on hair and
  fast hands (JOB-60 decides whether a matting-model candidate is filed, which must carry a licence
  an Apache-2.0 app can ship); backlit, from-behind and small figures are missed; a composition must
  not colour-manage a mask (CO-S2 (2)); each cut-out layer reads and decompresses one mask from
  its pack per frame (CO-S2 (5), (6)); the pack is lossless, 62.32 MB a minute (CO0's record); GPU
  and Neural Engine masks differ by up to 25 levels across Macs.
- **Layouts against existing placement.** A switch rewrites the base placement of role clips up to
  the next layout action; hand placement there is overwritten unless `through` bounds the reach;
  zooms in the reach are refused and nested, and a nested screen or camera loses rounded corners;
  CU's Auto Zoom on a side-by-side screen fills the canvas (the remedy is a nest; CU-75 refuses it).
- **Vertical versions.** A 1080p source upscaled ×1.78 looks soft (the guide says shoot 4K); the
  wrong subject can win (a poster, a monitor face); composition inside existing actions is
  approximate and re-eases split actions (counted); a moving motion preset is kept and excluded from
  coverage; the decoder budget warns past 8; VR-41 changes Subtitles and Text ▸ Presets on every
  portrait project (landscape and square byte-identical); graphics written by people or agents may
  overflow a tall frame; the copy drifts from the master until linked versions.
- **Several 4K angles and multi-hour files are unmeasured** until SW-S2: cuts between long-GOP files
  may hitch (SW2c), a thousand-shot rebuild may be slow, four live 4K decodes beside the program may
  exceed the decoders; SW-S2 costs about 34 GB and up to an hour of encoding. A shortfall is a
  recorded limit and a Performance issue; no proxies are built.
- **Audio streams.** AVFoundation's handling of many-channel streams is unmeasured (SW-S1 picks the
  tap or a mono copy at about 0.5 GB an hour per channel); its stream order may differ from the
  container's; iPhone Spatial Audio may add undecodable tracks; media imported before SW3a need a
  relink to the same file; per-source caches multiply sync and speech files; link groups rewrite
  every link rule.
- **The switch trusts the placement;** a slipped or moved shot falls out of sync, and one bleed
  margin will not suit every room (SW-S4 tunes it; the sheet exposes it). Mouth activity fails on
  profiles, small faces, beards and hands (SW-S3 gates SW8).
- **Shared files across three lanes.** The layer stage, the recipe, `LayerUniforms`, the recorder
  panel, `op_rows.rs`, `edit.rs`, `scope.rs`, `ReelOps.swift`, the menus, `UIMenuTable.swift`,
  `inventory.json`, the decision file, the spec index and the pinned counts take rows from several
  lanes; the integrator resolves them one landing at a time (CJ-6, CJ-8), and T8 moves the busiest
  two out of a frozen file. Provisional format numbers (ten, eleven with VR7a) are renumbered at
  landing.
- **The unmerged tutorials branch.** `worktree-tutorial-handler` (98 files, about 9,700 lines; the
  owner's TU4 trial owed) resolves tutorial targets through `InspectorTab.allCases` and menu titles
  (`TutorialTargetResolver.swift`, `TutorialTargets.swift`) and edits `v2_menu.py`, while this road
  map adds a fifth `InspectorTab` case before Assistant (TX2a) and about twenty menu items, windows
  and panels. **The integrator's duty:** if the tutorials branch merges into main while creator-jobs
  runs, the later of the two to land on main adds a `TutorialTargets` row for each new tab, menu
  item and window that a tutorial could point at, re-checks every existing target that named a tab
  by index, and reconciles `v2_menu.py`'s rows once, in that landing; the record names the rows.
- **The helper is shared with Rasterize.** FC5's diff must land in both, or `agent/src` stops being
  one file set.
- **The assistant's search guide** is at 1,498 of 1,500 characters; FC's clips row must take words
  from other rows (F6 checks it).
- **Samples may not come.** Quality claims then rest on JOB rows, and CJ-S2's face share, S-KEY1's
  ground truth and S-EV's recall stay owed. The samples are personal and are never committed or sent
  without a spike's flags and the month's budget.
- **The trials may reorder the road map** (an amendment of CJ-2).
- **API drift.** Apple may deprecate the `VN*` classes for the `async`-only Swift API; W-8 confines
  `async`, so that would need a decision.

## Questions asked at phase time

Each with its recommendation; the phase asks before its code, and the answer is recorded with its
decisions.

- **CJ0a:** (1) merge per phase or at close — *per phase*; (2) lift §2's "Left out" — *yes*; (3)
  samples' home and timing — *`tools/proof/media/creator/`*; (4) survey decision 8's measurement —
  *yes, as SW0*; (5) the literal reading of GR-20, GR-27…GR-30, AU-2's and G-1's clauses — *yes,
  nothing built*; (6) the owner's own answer, "ReelCore.swift should be extended to multiple files":
  `ReelCore.swift` and its `ReelCore+<Area>.swift` files may call `rc_*`, each new wrapper in the
  file of its area, recorded as CJ-8 (l), no Rasterize issue; (7) survey decision 3's TR-3, AI-6,
  W-9 and `recording.md` amendments, read from "Add all" — *yes*; (8) survey decision 5, linked
  versions as well as the copy — *yes, VR7a–VR9 after VR4 and SW7a, VR-S4 first* — answered
  2026-11-01.
- **CJ1:** Remove Filler Words stays usable with a cached filler transcript and no key — *yes*; View
  ▸ Assistant stays enabled — *yes*; the sixth parity part — *yes*; a disabled keyed menu item's
  title suffix naming its key, beside the tooltip — *yes, by default; JOB-1 may drop it*.
- **CJ2b:** Split at Shot Changes as the lane's first door — *yes*.
- **CJ5b:** the new document opens with the range as its first state — *yes*.
- **CJ6:** raise `MAX_CLIPS` to CJ-S1's N if it passes — *yes*.
- **TX1:** same speech on two tracks — *show both and name the pair*; fill only when asked — *yes*;
  read each media whole — *yes*.
- **TX2a:** the host — *the fifth inspector tab*; the title — *"Transcript" if T1 passes, else
  "Words"*; a timeline click while the transcript shows — *stay and scroll*; ⌃⌘T — *yes*; ⌘F —
  *later, unless free*.
- **TX3:** ⌫ ripples in the transcript, lifts on the timeline — *yes*; a word selection sets the
  in/out range — *yes*.
- **TX4:** a restore longer than one track's cut — *fill what each track has and leave a gap*.
- **TX5:** Restore's key — *Return on a greyed selection, the menu item with no key equivalent*; 40
  words inline — *yes*.
- **TX6:** long pause at 1.0 s keeping 0.2 s — *yes*; strikes as a timeline wash — *yes*.
- **TX7:** retakes on by default — *on if TX-S4 passes on your read, else off with restarts and
  repeats on*; the hand-off button — *yes*; TX-S4's paid AssemblyAI read of S-RT1 (about a cent) —
  *yes*.
- **TX8:** the figures recorded beside CJ-5's criteria — *yes, agreed before TX1's code*.
- **CU0b:** any STOP verdict is put to the owner before CU1a, with its rule's recommendation —
  clicks: *positions only, zooms on dwells and dirty rects*; keys: *CU6 and CU8 filed, Accessibility
  never asked*; display mapping: *the cursor file as data, the drawn cursor filed*.
- **CU1b:** the cursor file beside the movie — *yes, `<stem>.fjcursor`*.
- **CU3c:** the default — *Separate, unless CU-S2's Separate rows failed*.
- **CU4:** the look a recording lands with — *as captured, plus ripples with Show Clicks*.
- **CU6:** the indicator — *keyboard mark plus menu row*; ⌥ with arrows, delete, return, tab, escape
  as a shortcut — *yes*.
- **CU7:** Replace's default — *off*.
- **CU8:** overlay position and theme — *bottom, dark*.
- **CU9b:** sound in a sped stretch — *sped with Keep pitch on*.
- **CU10:** the landing checkboxes' defaults — *zoom on, shortcuts on when recorded, speed-up off*.
- **CU11:** the shutter Auto Zoom sets — *50 %*.
- **CO0:** if CO-S2 passes neither the mask track nor the mask pack — *file the video cutout, build
  CO10's stills, go on with CO6–CO9*.
- **CO1:** a cut-out clip's analysis starts at once — *yes, with CJ-S3 (b)'s pause if chosen*.
- **CO2b:** a pending cutout drawn uncut in the preview — *yes, the status saying so*.
- **CO3:** a key equivalent for Remove Background — *none*.
- **CO4:** Best as the default on a short clip — *no: Standard always, Best per clip*.
- **CO5:** a clip flag or a track flag — *a clip flag*.
- **CO6:** switch length — *0.5 s, ease in and out*; the nest offer or automatic nesting — *the
  offer*.
- **CO8:** the panel's default layout — *Corner (today's landing)*.
- **CO9:** fade or Screen Only on silence — *fade*.
- **CO10:** pictures in this road map — *yes, last*.
- **VR1:** Show Subjects in the product — *yes*.
- **VR2b:** default zoom — *fill*; two people who don't fit — *follow one*; headroom — *38 %*.
- **VR3:** offer 4:5 — *yes (VR-32)*; the copy's step as one undo step — *yes*.
- **VR4:** Re-lay Captions for This Canvas on its own — *yes (VR-45)*; re-page from the pages —
  *yes*; update old template copies in a vertical copy — *yes*.
- **VR5:** replace 16:9 auto zooms — *yes*; re-lay a screen and its camera instead of following the
  cursor — *yes, in VR5b*.
- **VR5b:** Side by Side becomes Stacked on a tall canvas — *yes*.
- **VR6:** match faces to mics automatically with the sheet confirming — *yes*.
- **VR7a:** asked at CJ0a (question 8) — *yes*; the vertical trial may withdraw it before VR7a.
- **VR8:** the popup in the toolbar and View ▸ Framing ▸ — *yes*; only X, Y and Scale in a framing —
  *yes*; a clip added after the framing — *`keep` until framed*.
- **VR9:** the sheet's default once linked versions land — *Add to This Project*.
- **FC3:** run the sound pass at import — *no*.
- **FC4:** bounds 20–60 s and pool 3 × count — *yes*.
- **FC5:** Rasterize applies the same `agent/` diff through one issue — *yes*.
- **FC6:** a keyed `rank_clips` for outside agents — *no*; rank with the Assistant's model — *yes*;
  titles and reasons in the transcript's language — *yes*; a classifier refusal ends the run —
  *yes*.
- **FC7a:** a window rather than a sheet — *a window*.
- **FC7b:** show the ceiling as well as the band — *both*.
- **FC8a:** default Export row and loudness — *H.264 MP4 at the canvas size, −14 LUFS*; remove
  pauses in a short — *not by default*.
- **FC9:** the default shape — *9:16*.
- **SW0:** build F-4K — *yes, once*; a generated three-hour file or wait for S-LONG1 — *wait*.
- **SW1:** ⌥1–⌥9 for Switch Angle — *no (bare 1–9 come in SW9b)*; keep a shot's own video settings
  on a re-pick — *no*.
- **SW2a:** the defaults as SW-S4 tunes them — *yes*.
- **SW2b:** the program track — *yes*; `wide_after` — *offered, off*; cut to the wide on laughter —
  *not here; a candidate*.
- **SW3a:** the default track — *track 1*; ask at import — *no*.
- **SW4a:** measure every track at import — *no: track 1 always, others when played*.
- **SW6:** the fold when AVFoundation's is unequal — *Frame Job's equal fold*.
- **SW7a:** groups — *yes*.
- **SW7b:** include OBS's mix track when detaching — *yes*.
- **SW8:** proceed at SW-S3's middle band — *yes, with SW-82's hedge*.
- **SW9a:** angles derived — *yes*; a panel beside the preview — *yes*; a multicam clip instead —
  *no*.
- **SW9b:** apply at stop — *yes*.

### The owner's answers (2026-11-01)

The owner walked through every question above on 2026-11-01, in nine batches. Each phase builds on these answers and records its own lines with its decisions. "Minor (taken as recommended)" marks an item that was listed to the owner as accepted unless they objected; they did not object. One answer departs from the recommendation: SW0 also generates the three-hour fixture now, rather than waiting for S-LONG1.

#### Batch 1: the key gate and shared phases
- CJ1:
  - Remove Filler Words stays usable with a cached filler transcript and no key: YES.
  - A disabled keyed menu item gets a title suffix naming its key, beside the tooltip: YES.
  - Minor (taken as recommended): View ▸ Assistant stays enabled; the parity check's sixth part.
- CJ5b: the new document opens with the range as its first state: YES.
- CJ6: raise MAX_CLIPS to CJ-S1's N if it passes: YES.
- CJ2b, minor (taken as recommended): Split at Shot Changes is the analysis lane's first door.

#### Batch 2: the Transcript tab
- TX1:
  - Same speech on two tracks: show both and name the pair.
  - Fill only when asked: YES.
  - Minor (taken as recommended): read each media whole.
- TX2a:
  - The host is the fifth inspector tab.
  - A timeline click while the transcript shows: stay and scroll.
  - Minor (taken as recommended): the title is "Transcript" if T1 passes, else "Words"; ⌃⌘T YES; ⌘F later, unless it comes free.

#### Batch 3: cutting and reviewing by transcript
- TX3: ⌫ ripples in the transcript and lifts on the timeline: YES. A word selection sets the in/out range: YES.
- TX6: a long pause is over 1.0 s, keeping 0.2 s: YES.
  - Minor (taken as recommended): strikes are shown as a timeline wash.
- TX7:
  - Retakes are on by default if TX-S4 passes on the owner's read; otherwise off, with restarts and repeats on.
  - TX-S4's paid AssemblyAI read of S-RT1 (about $0.01, cap $0.05): YES.
  - Minor (taken as recommended): the hand-off button to the Assistant.
- TX4, minor (taken as recommended): a restore longer than one track's cut fills what each track has and leaves a gap.
- TX5, minor (taken as recommended): Restore is Return on a greyed selection, with no key equivalent on the menu item; up to 40 words inline.
- TX8, minor (taken as recommended): the figures recorded beside CJ-5's criteria, agreed before TX1's code.

#### Batch 4: the cursor recorder
- CU0b: a STOP verdict is put to the owner (stop and ask), not taken automatically.
- CU1b: the cursor file sits beside the movie as `<stem>.fjcursor`: YES.
- CU3c: the default is Separate, unless CU-S2's Separate rows failed.
- CU4: a recording lands with its cursor as captured, plus ripples when Show Clicks was on.
- CU6:
  - The indicator is a keyboard mark plus a menu row.
  - Minor (taken as recommended): ⌥ with arrows, delete, return, tab or escape counts as a shortcut.

#### Batch 5: Auto Zoom, overlays, Speed Up Typing
- CU7: Replace's default is off.
- CU8: overlays sit at the bottom, in the dark theme.
- CU9b: the sound in a sped stretch is sped with Keep pitch on.
- CU10: the landing checkboxes default to zoom on, shortcuts on when recorded, speed-up off.
- CU11, minor (taken as recommended): the shutter Auto Zoom sets is 50 %.

#### Batch 6: cutout and layouts
- CO0: if CO-S2 passes neither the mask track nor the mask pack, file the video cutout, build CO10's stills and go on with CO6–CO9.
- CO4: Best is not the default on a short clip; Standard always, Best per clip.
- CO6:
  - A switch takes 0.5 s, eased in and out.
  - Minor (taken as recommended): the nest is offered, not automatic.
- CO9: on silence, fade.
- Minor (taken as recommended):
  - CO1: a cut-out clip's analysis starts at once, with CJ-S3 (b)'s pause if chosen.
  - CO2b: a pending cutout is drawn uncut in the preview, with a status saying so.
  - CO3: Remove Background has no key equivalent.
  - CO5: Behind Subject is a clip flag.
  - CO8: the panel's default layout is Corner.
  - CO10: pictures are in this road map, last.

#### Batch 7: Make Vertical Version
- VR2b:
  - The default zoom is fill.
  - Two people who don't fit: follow one.
  - Minor (taken as recommended): headroom 38 %.
- VR3:
  - Offer 4:5 as well as 9:16 and 1:1: YES (VR-32).
  - Minor (taken as recommended): the copy is made as one undo step.
- VR9: once linked versions land, the sheet's default is Add to This Project.
- Minor (taken as recommended):
  - VR1: Show Subjects is in the product.
  - VR4: Re-lay Captions for This Canvas exists on its own (VR-45); captions are re-paged from the pages; old template copies in a vertical copy are updated.
  - VR5: 16:9 auto zooms are replaced; a screen and its camera are re-laid in VR5b instead of following the cursor.
  - VR5b: Side by Side becomes Stacked on a tall canvas.
  - VR6: faces are matched to mics automatically, with the sheet confirming.
  - VR7a: YES (CJ0a question 8).
  - VR8: the popup goes in the toolbar and View ▸ Framing ▸; only X, Y and Scale are set per framing; a clip added after the framing keeps its own until framed.

#### Batch 8: Find Clips and Make Short
- FC3: run the sound pass at import: NO. It runs when Find Clips needs it.
- FC5: Rasterize applies the same `agent/` diff through one issue on kpgalligan/rasterize: YES (FC5 files it).
- FC6:
  - A keyed `rank_clips` for outside agents: NO.
  - Minor (taken as recommended): rank with the Assistant's model; titles and reasons in the transcript's language; a classifier refusal ends the run.
- FC8a: the default Export row is H.264 MP4 at the canvas size, −14 LUFS. Removing pauses in a short is not the default.
- Minor (taken as recommended):
  - FC4: bounds 20–60 s and a pool of 3 × count.
  - FC7a: a window, not a sheet.
  - FC7b: show both the ceiling and the band.
  - FC9: the default shape is 9:16.

#### Batch 9: Switch by Speaker and multi-track audio
- SW0: build F-4K once: YES. **The three-hour file: BUILD BOTH NOW.** That means a generated three-hour fixture, not waiting for S-LONG1. This departs from the recommendation.
- SW2b:
  - The program track: YES.
  - `wide_after` is offered and off.
  - Cutting to the wide on laughter is not built here; it is a candidate to file.
- SW3a: the default track is track 1; no asking at import.
- SW4a: track 1 is measured at import; the other tracks when played.
- SW9a:
  - Angles are derived: YES.
  - A panel beside the preview: YES.
  - A multicam clip instead: NO.
- SW9b: switches made while playing apply at Stop: YES.
- Minor (taken as recommended):
  - SW1: no ⌥1–⌥9 (bare 1–9 come in SW9b); a re-pick does not keep a shot's own video settings.
  - SW2a: the defaults as SW-S4 tunes them.
  - SW6: Frame Job's equal fold when AVFoundation's fold is unequal.
  - SW7a: groups: YES.
  - SW7b: OBS's mix track is included when detaching.
  - SW8: proceed at SW-S3's middle band, with SW-82's hedge.

## Not in this road map

Nothing below is excluded: the spec names no non-goal since CJ-1. Each item is simply not built by
these phases; a later road map may take any of them up.

- **The survey's next tier**, neither in nor out: Proposals (an agent's multi-step edit played
  before it lands; amends AI-10) and Recipes; Punch in on cuts (it would read TX-42's cuts); source
  ranges on `add_clip`, `insert_clip` and `overwrite_clip`, skimming, In and Out on media and
  favourite ranges (no bet needs them: TX-41 composes its own primitives and FC places by
  `keep_range`); caption styles, a brand kit and project templates (W-10); the publish polish slice
  (a 00:00 chapter list, safe-zone overlays, named platform export rows); `search_media` over cached
  transcripts; merging the in-app tutorials after TU4; optical-flow slow motion; WebVTT import and
  translated captions.
- **The survey's "Not worth chasing"**, neither in nor out and not built here (the survey's
  judgement of their worth, not an exclusion; its stabilisation, plugin system and motion blur are
  §1 items CJ-1 lifted): generative media and dubbing; direct upload,
  scheduling and analytics; stock libraries and a template marketplace; eye contact and retouching;
  cloud sync, collaboration, mobile and Windows; remote guests and live multi-camera capture; a
  virality score (FC-67 forbids one); a standalone footage index; script-to-cut; translated subtitle
  tracks as a bet; a publish kit; more MCP surface as a headline; stabilisation; live-compositor
  motion blur beyond CU11; a plugin system; pro finishing; analytics-driven features.
- **Lifted by CJ-1 and not built here:** other platforms, a plugin system and scripting beyond
  graphics (G-1 stands), third-party Audio Unit hosting (AU-2 stands), stabilisation, optical-flow
  retiming, proxies (only after a measured shortfall, as a Performance issue), and GR-20 and
  GR-27…GR-30.
- **Language models:** Apple FoundationModels, any on-device language-model fallback, an on-device
  filler pass (TR-7 stands), a Frame Job relay or account (C2, #125 stays iced), the Keychain for
  keys (R6-5's measured reason stands).
- **Left out of the bets' scope, not excluded** (each filed as a candidate at the close where
  useful): editing a word's text;
  background fills on import; a detachable transcript window and Find (⌘F) unless chosen; a merge op
  rejoining restored halves; diarisation without AssemblyAI; script-first recording, a teleprompter,
  regenerated speech, translation (TX). Reconstructing a cursor for older or imported recordings;
  typed text as overlays (an "all keys" mode); click sounds, cursor packs and styles beyond As
  recorded and Arrow; other callouts (arrows, highlights); a global record hotkey (CJ-4); frame
  interpolation for sped-up typing; live auto zoom while recording; recording an iOS device's screen
  (CU). Masks or any per-pixel subject work for framing; following clips inside a nest, matte pairs
  or rotated clips; a range of the timeline as a vertical version (it is New Project from Range or
  Make Short, then Make Vertical); File ▸ Duplicate; keyframes (VR). Ranking without a key or for an
  outside agent unless `rank_clips` is chosen; publishing; clips across projects; B-roll, music,
  zooms or punch-ins in a short; removing pauses in a short; visual signals as readings (FC). A
  multicam source kind (SW-3); virtual angles cropped from one wide camera; laughter to the wide;
  telling speakers apart by voice on one microphone with no faces (keyed if built); side-by-side
  layouts during crosstalk; exporting the multicam edit as FCPXML or AAF; a multitrack movie as an
  export (AU-101 stands) (SW). One command to replace or blur the background; choosing one person
  among several, a mask brush, rotoscoping; non-person cutout on video; a cut-out preview in the
  recorder; layouts with several cameras; face-tracking zoom on the camera; a shipped or downloaded
  matting model unless JOB-60 asks (CO).
- **Any change to G-1's "a graphic is a source", AU-2, R5-1 or "a recording is ordinary media"**
  beyond what a phase above amends in writing (CU-2): they stand as current design (CJ-1), which a
  later road map amends in writing before its code.
