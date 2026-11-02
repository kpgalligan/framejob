# Spec §11 — decisions: Creator jobs, the cursor file onward (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) (CJ-, VR-, TX-, SW- and CU-),
so a citation never has to say which file; that file says what the road map builds and how its
IDs are made (CJ-7). This file is new because `creator-jobs.md` passed the road map's ~500-line
split rule with CU1a's entries (2026-11-01), which moved here; each phase's decisions are
appended here from now on, before its code.

- **CU-10 — Cursor file format v1, owned by `cursor_file.rs` (CU1a; CU-S4 `body=json`).** One UTF-8
  JSON object; `RC_CURSOR_FILE_VERSION` (1) is in the header. The header keys: `format`
  ("framejob-cursor"), `version`, `in_picture`, `source` (`display`, `window`, `picked`),
  `display_id`, `source_frame` (the SCDisplay or SCWindow frame at open, M3's input),
  `point_size`, `pixels_per_point`, `content_size` and `movie_size` (px, 1…16384), `anchor` (`e2`
  or `e1`) and `anchor_host_us`, `cursor_image` (`current-system` or `none`). The columns, every
  time integer µs from the movie's first frame and every position points × 100 in global display
  coordinates: `moves`, `images` (base64 PNG, hot spot, point size, `kind` from a closed list;
  the id is the index), `image_changes`, `hidden` spans, `clicks` (button 0…31, down 0 or 1,
  count ≥ 1), `scrolls` (`dx`/`dy` the event's signed point deltas as delivered, after the
  system's scroll direction, × 100; line deltas not stored), `geometry` (≥ 1 entry, every CU-S2
  candidate's inputs: `screen_rect`, `content_rect`, `content_scale`, `scale_factor`), `dirty`,
  and `keys` (`shortcut` {t, keys, code}, `typed` {t}). `hidden` and `dirty` stay empty until
  CU-S1 and CU-S3 pass; `keys` stays empty until CU6. **Parse order:** a loose read first — not an
  object, then `format`, then `version` (absent, not an integer, below 1 or above 1, "…is version
  N; this Frame Job reads cursor files up to version 1"), then CU-7's `typed` keys — and only
  then the strict `deny_unknown_fields` parse through `serde_path_to_error` and the check, so a
  newer file is refused by its version and a project by its format. The check refuses, each in its own sentence,
  columns of unequal length, an array over its cap (moves, scrolls and dirty 1,728,000 each;
  clicks 200,000; images 1,024; a PNG 1 MiB; image changes 1,000,000; hidden, geometry and
  shortcuts 100,000; typed 1,000,000), a negative time or one going back within a column, an
  empty, overlapping (touching allowed) or out-of-order hidden span, an image id out of range,
  base64 that does not decode or bytes without the PNG signature, a hot spot outside its image,
  images under `cursor_image: none`, a word outside its vocabulary, a float not finite and above
  0, and CU-7's rules: a `typed` entry with any key but `t`, and a shortcut whose `+`-joined
  tokens are empty, hold whitespace, or hold neither `cmd` nor `ctrl`. The core does no file I/O
  and checks a PNG by its signature only.
- **CU-14 — A cursor file that fails to write or read back is that segment's `cursorProblem` and
  the landing's note, never the recording's failure.**
- **CU-15 — One file per segment movie, `<stem>.fjcursor` beside it.** `CursorFileWriter` writes
  `<stem>.fjcursor.partial`, reads it back through `ReelCursor` (the core's `rc_cursor_open`), and
  only then `rename(2)`s it into place, replacing any file there. On a failure both paths are left
  empty and the problem carries the core's sentence.
- **CU-16 — The header's two sizes:** `content_size` (the stream's points × pixels per point) is
  the mapping's; `movie_size` (the written track's, the encoder rounding an odd side up) is
  import's match.
- **CU-17 — `CursorCaptureBuffer`'s rules: a body it writes is always one the core accepts.**
  `openSegment` resets every array and the dedupe state (the last image id, the last geometry) and
  records the start's `geometry` as the latest one before the anchor; a sample fed while closed is
  dropped. `closeSegment(movieSize:anchor:)` (beside `movieSize:` because E2 is answered or
  dropped by then) writes times `round((host − anchor) × 1e6)` µs, positions and scroll deltas
  `round(pt × 100)`. Before the anchor the latest move, image change and geometry are kept at t 0,
  every event is dropped and a hidden span is clipped at 0. Each column is stably sorted by time;
  hidden spans are then clipped, dropped when empty after rounding, and merged when they overlap
  or touch. Images are interned by their PNG bytes; an image change is recorded only when the id
  differs, a geometry entry only when it differs from the last. Under `cursor_image: none` image
  samples are dropped, and `current-system` with no image recorded writes `none`.
  `CursorAnchor.choose(e2:e1:)` picks E2 when given, else E1.
- **CU-20 — The mapping, provisional: M1 (CU2).** Movie px = `(p − screen_rect.origin) ×
  content_scale × pixels_per_point + content_rect.origin × pixels_per_point`, every file value
  ÷ 100 to give points. The geometry entry used is the one in force at the sample's time: the last
  with `t ≤` it, or the first entry before any. One function computes it, and movie px = content
  px (CU-16). CU-S2's verdict is owed (JOB-29), so M1, the first candidate in its rule, stands for
  every source kind; the phase that records CU-S2's verdict amends CU-20 and that function if M2
  or M3 wins. `px_per_point` = `content_scale × pixels_per_point`. A source tick T and a file µs
  convert through `time::ticks_to_seconds` / `seconds_to_ticks` × 1e6 (file t 0 is source tick 0).
- **CU-21 — Smoothing (CU2).** `smoothing` runs 0…1. **The hold rule**, one implementation
  (`cursor_smooth::hold_end`): moves are recorded only when the position changes, so when moves i
  and i+1 are more than `HOLD_GAP_US` 25,000 µs apart the cursor holds move i until `t[i+1] −
  POLL_US` (8,333 µs), then moves linearly; a time inside a hold answers the held position
  exactly, at every smoothing. **0** is the raw moves linearly interpolated with the hold rule, no
  precompute and no pins. **Above 0** (`SmoothPath::build`): the pins are the file's first and last
  moves, every down click's `(t, x, y)` (replacing a move at the same t) and both ends of every
  hold; between consecutive pins Ramer–Douglas–Peucker runs at a tolerance of `TOLERANCE_PT` 12 pt
  × smoothing, keeping the segment's ends; the kept points (pins ∪ RDP's) are evaluated as a
  centripetal Catmull–Rom spline in time (α ½, Barry–Goldman, the ends' neighbours duplicated, a
  knot step floored at 1e-6, `u = (at − t_i)/(t_{i+1} − t_i)` mapped onto the knot span). The path
  is non-causal and passes through every click. **Storage:** only `prepare` stores a smoothed path,
  computed outside the lock; the core never drops a stored smoothing on its own, only on an
  `unprepare` request, and the registry owns the cap (CU-26). `path` at an unprepared smoothing
  builds one for that request and stores nothing; `state` at an unprepared smoothing answers the
  raw path and never builds one. Before the first move the answer is the first move; after the
  last, the last.
- **CU-22 — Idle hide (CU2).** Activity is every move and every down click. With `hide_idle` h s
  the opacity is 1 while `at − L < h` (L the last activity ≤ at), then falls linearly to 0 over
  `IDLE_FADE_US` 200,000; from `N − IDLE_LEAD_US` (N the next activity, the lead 150,000) it is 1
  again at once. Inside a recorded `hidden` span `[from, to)` the opacity is 0, whatever else
  holds. With no moves at all `visible` is false; `visible` is opacity > 0.
- **CU-23 — Ripples (CU2).** Each down click is active for `RIPPLE_US` 450,000 after its t, with
  `phase = (at − t)/450,000` in [0, 1), at the click's own position. Ripples are answered only with
  `clicks: "ripple"`, newest first, at most `MAX_RIPPLES` 4 (the shader's slots). Idle and hidden
  spans do not affect them.
- **CU-24 — A file newer than the core is refused by its version, and its clip draws without a
  cursor (CU2).** `rc_cursor_open` refuses it by CU-10's sentence; `CursorTracks` keeps that
  sentence as the path's failure and answers no track, so the clip draws without a cursor (CU3a2
  draws, CU-37 warns).
- **CU-25 — The request vocabulary of `rc_cursor_query` (CU2).** One JSON request, one key, strict
  (an unknown key refused), answering JSON; ticks are source ticks, positions movie px (f64), times
  half-open `[from, to)`. `prepare {smoothing}` → `{prepared: {smoothing, kept}}` (at 0, `kept` is
  the move count and nothing is stored); `unprepare {smoothing}` → `{unprepared: bool}` (false when
  it was not stored, always at 0); `state {at, props: {smoothing?, hide_idle?, scale?, clicks?}}` →
  `{visible, x, y, opacity, px_per_point, image: {id, w, h, hot_x, hot_y} | null, ripples: [{x, y,
  phase}]}`, `props` ignoring other keys so the recipe's object may be passed, image sizes points ×
  `px_per_point` × `scale`, `image` null under `cursor_image: none` or before the first image
  change; `image {id}` → the PNG as base64 with its point size, hot spot and `kind`; `events {from,
  to, kinds}` → only the asked keys of `clicks`, `scrolls`, `shortcuts` and `typing` (a typing
  stretch is `typed` marks under 1.0 s apart, at least 3 of them, answered when it overlaps the
  range); `path {from, to, step, smoothing}` → `{t, x, y}` sampled at from, from + step, … < to,
  the step at least 60,000 ticks (10 Hz) and at most 144,000 samples. `path` is VR5's read and
  never stores a prepared path. The compositor reads only `CursorTracks.ready` and `state`; it
  never opens a file or prepares a path. `project` is unused by these six requests (the planners
  use it later). Each refusal is its own lowercase sentence through `err_out`.
- **CU-26 — `CursorTracks`, the process-wide registry (CU2; `RampAudioRenders`' owner shape).**
  Tracks are keyed by path with the file's size and modification second, read by stat at `want`; a
  change reloads. Each owner's latest `want` set is pinned until it is replaced or
  `release(owner:)` is called; `wait(for:owner:)` first wants its set under its owner, so an
  export's set stays pinned until the export releases it. A pinned (path, smoothing) is never
  evicted, however many there are. Both caps count every held entry, pinned included; only unpinned
  ones go: past `capacity` 8 paths the least recently wanted unpinned path is closed, and past
  `smoothingsPerPath` 4 prepared smoothings on a path its least recently wanted unpinned one dropped.
  A drop removes the `ready` entry and queues `unprepare` in one lock hold, ahead of any later
  `want`'s prepare, so `ready` never answers a smoothing the core has dropped; a `want` re-lands it. One
  serial `.utility` queue loads (the dev hold `-RCDevCursorLoadHold <s>` first), opens, prepares
  and unprepares; `ready` reads a locked dictionary only. Each (path, smoothing) landing posts
  `.cursorTrackDidLand` once on main. A failed key is not retried until its size or modification
  second changes. `RecipeSource.set` and `Playback.update` are wired by CU3a2, when the recipe
  carries cursor media (a deviation from the road map's CU2 text: no media has a cursor before
  CU3a1).
- **CJ-10 — `ModelKeys` is the one test of whether a key is present (CJ1; the owner's CJ1 answers,
  2026-11-01: (1) Remove Filler Words stays usable with a current filler transcript and no key;
  (2) View ▸ Assistant stays enabled with no key; (3) the parity check gains a sixth part; (4) a
  disabled keyed menu item's title gains a suffix beside its tooltip).** `ModelKeys.swift` holds
  `ModelKey` (`anthropic`, `assemblyAI`) and `ModelKeys`: `present(_:store:environment:)`, whose
  defaults are the key's own configuration's `store()` (`AssemblyAIConfiguration.store()`,
  `AssistantConfiguration.store(environment:)`) and the process environment, and which answers
  whether that configuration's `credential(store:environment:)` resolves, so R6-9's and AI-13's
  proof isolation is unchanged and the sheets keep passing their injected store and environment;
  `sentence(_:)`; `refusal(_:)`, a `ToolError` with the sentence; `require(_:)`; and two marking
  helpers. `mark(control, missing:, enabled:)` sets `isEnabled` to `enabled` and the tooltip to the
  missing key's sentence, or nil when `missing` is nil; `mark(item, missing:, enabled:)` sets the
  item's title to its base title plus the missing key's suffix — " (needs your AssemblyAI key)" or
  " (needs your Anthropic key)", assigned only when it differs — and its tooltip the same way, and
  answers `enabled`. `enabled` is always the caller's whole rule, key term included, and `missing`
  says only why it is off: neither helper overrides it, so each caller's own key term stays the
  gate its mutants test. `ModelKeys.didChangeNotification` (`userInfo` `key`, the source key's raw
  value) is posted after either key's own notification — `SettingsWindowController`'s for
  AssemblyAI, `AssistantConfiguration`'s for Anthropic — by one observer of each, installed once,
  lazily, by `observe(_:selector:)` and by the first `mark(item…)`; each observer, synchronously
  and in this order, resets the main menu's satisfied marks (`clearSatisfiedMarks(in:)`: every
  keyed item whose key is now present gets its base title and a nil tooltip, nothing else changes)
  and re-posts. The reset is there because an item is otherwise re-titled only by its validator,
  which does not run while a sheet is up or with no editor in the responder chain. Nothing is
  memoised (a presence test is one small file read; a memo would be wrong for an injected store
  and stale when another Frame Job writes the key). Every read that decides "a key is present"
  moves here; the senders still read the credential to send it. `AssistantSettingsPane.swift`'s
  status line and `SettingsWindowController`'s panes are not gates and are unchanged.
- **CJ-11 — One sentence per key, for tooltips, notes and refusals:** "No AssemblyAI API key is
  set. Set one in Frame Job ▸ Settings… ▸ Transcription." and "No Anthropic API key is set. Set
  one in Frame Job ▸ Settings… ▸ Assistant." They replace `CloudTranscriber.AccessError`'s,
  `TranscribeSheetController.noKeyNote`'s (deleted) and `AssistantSession`'s words and every
  bet's own (TX-14, FC-70). The environment variables leave the person-facing sentence (they are
  in `docs/developing.md`). R6-17's precedence is unchanged, only its credential arm's words. The
  Assistant tab's no-key row keeps its call to action, which is not a disabled control. Each keyed
  tool's catalog description ends with its key's clause: "Keyed (spec §11 CJ-3): where it would
  send to <AssemblyAI | Anthropic> it needs the person's <AssemblyAI | Anthropic> API key, and
  without one it refuses there with "<the sentence>"".
- **CJ-12 — The keyed table; every keyed tool refuses in its own precedence.** `ModelKeys.keyed`
  lists each keyed feature: its name, its key, its menu selector (or none), its tools, and whether
  it is conditional (keyed only when it would send). A tool refuses only where it would send, after
  its own earlier refusals and any answer it can give from a cache; no tool is keyed before its
  arguments are read, so dispatch gains no key check. The shipped rows:
  - "Remove Filler Words" (AssemblyAI, Clip ▸ Remove Filler Words…, `transcribe_for_fillers`,
    conditional). `transcribe_for_fillers`' order is unchanged — the id, the cache directory, a
    clip playing the media, the ready arm (a media with a current filler transcript answers
    `ready: true`, `uploaded: []` with no key), then the credential. The menu item is disabled,
    with the AssemblyAI sentence as its tooltip and the suffix on its title, only when the project
    has a clip that plays sound from a media file, no AssemblyAI key is present AND no media in
    scope has a current filler transcript (`FillerTranscriptPresence.any`, which is
    `FillerDetector.read(from:clips: nil)` answering at least one clip). That answer is memoised in
    one entry keyed by the edited project's handle (held, compared by identity), the selection,
    the cache directory and the modification date of `<cache>/transcripts/` (nil when absent) —
    the date in place of the road map's "dropped on the transcript cache's posts", because the
    transcript cache posts nothing; a transcript written or removed renames an entry in that
    folder and moves its date. The Remove Filler Words sheet observes `ModelKeys`; a row's
    Transcribe is marked with the AssemblyAI sentence when no key is present.
  - "Generate Captions with AssemblyAI" (AssemblyAI, no menu selector, `transcribe`,
    conditional): `transcribe {engine: "assemblyai"}` keeps R6-16 and R6-17 but for the words;
    the Engine popup keeps AssemblyAI enabled (its cloud options must show for R6-16's reuse);
    Start, disabled without a key unless R6-16 admits the batch, carries the AssemblyAI sentence
    as its tooltip, which the on-device engine clears; the sheet observes `ModelKeys` in place of
    `SettingsWindowController`'s notification.
  - "Assistant" (Anthropic, no menu selector, `assistant_send` in a build with the dev tools and no
    tool in Distribution, not conditional): the composer and Send as today, View ▸ Assistant
    enabled (the tab says how to set the key), `assistant_send` refusing in the Anthropic sentence
    when the session opens.
  The bets add rows: TX6's `review_transcript {fillers}` and Fillers box, TX7's hand-off, FC7b's
  Rank.
- **CJ-13 — The startup parity check gains a sixth part:** every tool `ModelKeys.keyed` names is in
  the catalog, and its description contains its key's clause (CJ-11); every offender is named.
  `AgentServer.keyedToolFailure` in `AgentServer+Parity.swift`, chained after the fifth part in
  `AgentServer.swift`'s parity line, reported as the other five are.

CJ-28 and CJ-29 are CJ2b's (the Analyzing sheet and Clip ▸ Split at Shot Changes), recorded before its
code. The owner's answer of 2026-11-01 to the road map's CJ2b question — "Split at Shot Changes is the
analysis lane's first door" — was *yes* (taken as recommended). They were drafted as CJ-27 and CJ-28;
CJ2a took CJ-27 for `analysis_job`.

- **CJ-28 — One Analyzing sheet for every kind whose result a command plans with.** A menu command
  whose analysis misses the cache shows the sheet: title "Analyzing"; hint "\<command\> needs what
  Frame Job finds in these files on this Mac, kept in the project's cache. Nothing changes until it is
  found; Stop leaves everything as it is."; one row per media whose request missed — the file name, a
  determinate bar, "Waiting" until the job's first frame, then "NN %", then "Done" — polled every
  0.1 s (a `Timer` in the `.common` modes) from `AnalysisLane.progress(of:)` and `run(of:)`. Stop
  (secondary, Escape; `makeButtonRow` with a hidden primary, as `AudioSyncSheetController`) only
  dismisses: no edit lands, and what a job already published stays cached (CJ-21). The sheet wants
  every row's request under one lane owner (`alive`: `document.isOpenForAnalysis`; `settled`:
  `document.packageContentsDidChangeOnDisk()`) and releases it in `viewDidDisappear`, its one
  release, on every exit — Stop, landing, failure, the window closing. It calls `finished` once, on
  the main queue's next turn after `viewDidDisappear`: `.landed` when every run's outcome is
  `.landed`, `.failed` at the first failure; Stop calls nothing. A tool call shows no sheet and
  waits. While the sheet is attached every editor action validates false. The words are the menu's
  American verbs ("Analyzing"). CO-6 amends this for a render-substituted kind.
- **CJ-29 — Clip ▸ Split at Shot Changes and `split_at_shots {clips?}`.** A target is a media clip
  whose media is a video (`kind` `video`, `hasVideo`) and whose `enabled.video` is true; any other
  clip in the selection or `clips` is skipped (answered under `skipped`). The menu item validates on
  when a selected clip qualifies; with `clips` absent the tool takes every qualifying clip on an
  unlocked track in the scope. **One request per media over the union of its targets' played
  windows (`AnalysisClipTimes.window`), never their hull:** `document.analysisRequest` once per
  target window, and a media's miss `ranges` merged by `AnalysisStore.merged` into one
  `AnalysisRequest` (the first miss's other fields), so a gap no clip plays is never read. Each
  target's cuts are `AnalysisShots.cuts` over its own played window, mapped to clip time by
  `AnalysisClipTimes.clipTime(ofSource:)` (source map, speed, the reversed mirror), to timeline
  time `clip.start + clip_time`, snapped with `ReelTime.snapToFrame` to the canvas grid, and
  deduplicated; a cut is dropped when it lies within one canvas frame of either edge (`t − start ≤
  frame` or `end − t ≤ frame`, `Fps.frameDuration`). The ops are one `split {clips: [clip], at: t}`
  per cut, latest first, so the original id keeps the head; locks and partners are `split`'s (a
  named clip is cut, its linked partner only on an unlocked track, AU-92). **The ceiling, before any
  op:** `added` is Σ over the cuts of 1, plus 1 when the clip's partner exists, sits on an unlocked
  track and holds the cut strictly inside (`partner.start < t < partner.end`); the command is
  refused when `added > RC_MAX_CLIPS − clipCount`, `clipCount` the top level's clips and every
  nest's counted on the UNSCOPED project (`document.project`) in both doors, because a scoped view
  holds only the nest's clips while the core's `check_caps` counts every clip: "Split at Shot
  Changes would add N clips — each split counted with the linked clip it also cuts — more than this
  project has room for: M more clip(s) would fit, out of 4096." — the composite's own reading (D2-1,
  as `CaptionLayout`'s `tooMany`). It is one undo step, "Split at Shot Changes". When the project or
  scope changed while the sheet analysed, nothing is split: "the project changed while Split at Shot
  Changes was analyzing, so nothing was split. Choose Split at Shot Changes again." (the tool: "…
  Call split_at_shots again."). With no cut inside any target the command beeps and the tool answers
  `added: 0` with a note and no undo step. The planner lives in `ShotSplit.swift`, not in the
  editor's extension, because the tool calls it too (SY-1's shape). On device, no key (CJ-3); no
  core, FFI or format change (a composite of `split`, CJ-8 (f)).
