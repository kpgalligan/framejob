# Spec §11 — decisions: Creator jobs, the cursor file onward (road map "creator-jobs", from 2026-11-01)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md) (CJ-, VR-, TX-, SW- and CU-),
so a citation never has to say which file; that file says what the road map builds and how its
IDs are made (CJ-7). This file is new because `creator-jobs.md` passed the road map's ~500-line
split rule with CU1a's entries (2026-11-01), which moved here; each phase's decisions were
appended here, before its code, until it passed the same rule with CO0's entries, and the series
continues in `creator-jobs-3.md`.

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
- **CU-20 — The mapping: M2 (CU2; amended at CU1b1).** Movie px = `(p − screen_rect.origin) ×
  content_scale × scale_factor + content_rect.origin × scale_factor`, every file value ÷ 100 to
  give points, `scale_factor` the geometry entry's own (M1 with `scale_factor` for
  `pixels_per_point`). The geometry entry used is the one in force at the sample's time: the last
  with `t ≤` it, or the first entry before any. One function computes it, and movie px = content
  px (CU-16). `px_per_point` = `content_scale × scale_factor`. **Settled for displays** by
  CU-S2's verdict (`mapping_display=M2`, the owner's JOB-29 run, 2026-11-02); **provisional for
  window and picked sources**: M1 measured failing on window-odd and M2 passing both measured
  window rows, and the picked row is owed until the instrument's helper-owned window lets the
  owner perform it (before CU3c). A source tick T and a file µs convert through
  `time::ticks_to_seconds` / `seconds_to_ticks` × 1e6 (file t 0 is source tick 0).
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
  **Amended by CO-6 (CO0):** pending, cancelled and failed mask chunks draw the clip uncut; a
  render-substituted kind (`masks`) shows no Analyzing sheet; and a command that plans from masks
  reads only what is cached.
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

CU-30, CU-32, CU-35 and CU-39 are CU3a1's (the cursor in the model and the recipe), recorded before
its code, at format version 38 — provisional until the phase lands, the integrator renumbering a
collision. The road map drafted the media record's rule beside CU-30; it is CU-39 here because the
road map's draft CU-31 is CU3c's (the stream's cursor only In the picture).

- **CU-30 — `video.cursor`, a clip's cursor props (CU3a1, format 38).** `CursorProps` in
  `model_cursor.rs`, written only when set, after `video.look`, every field always written in
  declaration order: `show` (true), `scale` (1, 0.25–8), `style` (`recorded` | `arrow`, default
  `recorded`), `smoothing` (0, 0–1), `hide_idle` (null, or 0.5–30 s; written `null`), `clicks`
  (`none` | `ripple`, default `none`), `click_color` (`#ffffffcc`, a CSS colour in G-12's grammar,
  stored as given and read by `model_color::normalise_color`), `click_size` (1, 0.25–4); `{}` reads
  as all eight defaults. `set_video` accepts `cursor` on any clip and refuses, through
  `props_check::in_range`, "video.cursor.scale must be between 0.25 and 8, not 9" and likewise for
  `smoothing` (0–1), `hide_idle` (0.5–30) and `click_size` (0.25–4), and "video.cursor.click_color
  must be a CSS colour (spec §11 G-12), not "#ffg"". **In an action:** `scale` and `click_size`
  animate; `show`, `style`, `clicks` and `click_color` switch at the action's end; `smoothing` and
  `hide_idle` are the clip's — the recipe reads them from the BASE `clip.video.cursor` (0 and null
  when it has none), as `audio_track.rs` reads a base `audio.mono`, so an end may carry them (CI-3)
  and they have no effect. A split's second half and a freeze's still keep the original's BASE
  `smoothing` and `hide_idle` (`cursor_props::with_base_cursor`), so no splitter turns an end's
  values into a base. On a clip with NO `video.cursor` an end's cursor keys all switch at the end,
  as `shadow` and `look` do (§5.4: the absent key has nothing to lerp from); `set_video {cursor:
  {}}` stores the defaults, after which `scale` and `click_size` animate. **The evaluator's clamp**
  (`clamp_cursor`, never failing, so the video group always decodes): each number to its range,
  NaN to its default (`hide_idle` NaN → null); `click_color` normalised, an unreadable one
  `#ffffffcc`.
- **CU-32 — The recipe's `cursor` key, a layer's 27th, after `dissolve` (CU3a1).** `null` unless
  the clip's source is `media` or `still`, its media has `media.cursor`, that cursor's `in_picture`
  is false, and the evaluated `show` is true or `clicks` is `ripple`. Otherwise `{media, at,
  reversed, smoothing, hide_idle, props}`: `at` is `in + source_read_by(clip, clip_t)`, at least
  0, for a `media` source — `freeze_frame`'s expression: round(S) on a ramp, the base rate
  otherwise, in the stream the clip plays, the reversed one when reversed — and the still's own
  `at` for a still; `reversed` is the source's flag (false for a still), and the core mirrors
  nothing (D4-6); `smoothing` and `hide_idle` are the base's (CU-30); `props` is all eight keys of
  the evaluated, clamped props with the base's `smoothing` and `hide_idle`, so it passes whole to
  `rc_cursor_query`'s `state` (CU-25). The burn-in's is `null`; Show Ungraded and Show Selection
  leave it alone. `recipe_cursor.rs` writes it, `RecipeLayer` publishes it.
- **CU-35 — A project with no `media.cursor` writes, saves and draws as before (CU3a1).** Neither
  key is written unless set, so every older file writes the text it did at 38 with no migration
  step; every layer gains `"cursor": null` (always written, as `matte`), and a media whose cursor
  is `in_picture: true` publishes `null` too.
- **CU-39 — `media.cursor`, a media's cursor file (CU3a1, format 38).** `MediaCursor {path,
  bookmark?, in_picture}` in `model_cursor.rs`, after `speech`, written only when set, `bookmark`
  only when set; `in_picture` is required. `add_media`'s descriptor stores it; `check_media_fields`
  (`add_media`, a relink's probe, a pasted media row) refuses "media cursor path must not be empty"
  and, on any media not kind `video` with `has_video`, "media.cursor needs a video media with a
  picture, not an audio media" — "an image media", "a LUT media", "a video media without a
  picture". The bookmark is stored as given. A probed `relink_media` replaces it (a probe without
  one clears it); no probe — Consolidate, the open-time re-anchor — keeps it; paste carries it with
  its row; `validate` does not check it. Until CU3b the app's probe never carries one, so Relink…
  clears it.

TX-10…TX-14 are TX1's (`get_timeline_transcript`), recorded before its code. TX-S1 ran at the
phase's head on 2026-11-01 (its rule's `rule_sha256` `5f784283…2b65d548576861d12ff1d25b2c043b`
matches CJ0a's table): outcome A and `.userInitiated`, the numbers in TX-12. The owner's TX1 answers
of 2026-11-01: (1) two tracks carrying the same speech — show both and name the pair; (2) fill only
when the tab shows or a tool asks, never after import — yes; (3) read each media whole (minor,
taken as recommended).

- **TX-10 — The timeline transcript reads the words of every heard instance of a media clip in the
  edited container, nested ones included, in timeline order.** The edited container is the open
  nest when one is open (`document.editedProject`), else the timeline. **Instances** are the plan's
  audio segments of positive duration (the core's one flattening walk). The plan gains two keys on a
  NESTED audio segment only (`voice.stages.len() > 1`), after `automation`, as `track_pans` is
  written only when needed: `path` (the enclosing nest clip ids outermost first, then the clip's
  own — `Instance::path`, `voice.stages` ids reversed) and `origin` (the project time of the inner
  clip's first frame, `stages[0].origin`). A top-level segment carries neither, so every plan
  without a nest is the text it was (the plan is not persisted: no format change); Swift's
  `PlanSegment` reads `path` (default the clip alone) and `origin` (nil) leniently. An instance is
  read when its inner clip (from the container's clips or any nest's) passes `Transcriber.jobs`'
  gate on its own `ClipSnapshot` — its source map, for a nested clip, the scoped handle of the nest
  that holds it — and its plan track's envelope is not zero throughout the segment
  (`SilenceDetector.isAudible`: mute, solo, volume 0 and the same on an enclosing nest's track drop
  its words). **Words** come by TR-11's order — the media's cached transcript when its marker serves
  `.captions`, else this Mac's (TX-12) — as source words: a cloud word at
  `MediaTranscript.sourceTicks(milliseconds:)` of its start and of `max(start, end)`, a device word
  at its stored source ticks. A source word whose start lies in the job's window `[in, in +
  length)` is placed by R6-10's mapping (`MediaTranscript.project`, through S for a ramp); a nested
  word moves by the segment's `origin` less the inner clip's start and is kept only when its start
  lies inside the segment's span. **Order:** start, end, track (front first: the container track's
  index descending; a nested word's track is its enclosing nest clip's, `PlanTrack.track`), source
  order. **Identity:** `id {nest_path, media, source, k}` — `nest_path` the segment's `path` without
  its last id (empty on the timeline), `source` the word's source start tick, and k counting the
  earlier words in TX-10's order with the same nest path, media and tick, over every instance of
  that media in the container BEFORE the window, `tracks` and paging (0 unless one source plays
  twice). The inner clip's id is left out because a ripple gives every split's second half a fresh
  id. **No words:** `no_words` lists, once per clip id, every `.media` clip the gate refuses, found
  by walking the clips — the edited container's and, recursively, those of every nest a nest clip in
  it shows, unwindowed — NOT the segments (the core places no audio segment for a clip with its
  audio off or a media without audio): `{clip, nest_path, tag, reason}`, `tag` "clip 12" or "clip 12
  in nest Intro" (the nest that holds it), `reason` the gate's sentence, `nest_path` the nest clip
  ids leading to it (the first nest clip showing it, outermost first). Silently absent: a muted or
  zero-envelope instance, and a clip that passes the gate but has no segment (a frozen still, a
  speed above `AUDIO_SPEED_MAX`, an enclosing nest clip's audio off). **The same speech twice:** over
  the windowed words before `tracks` and paging, two clips of different media whose instances
  overlap on the timeline for at least 5 s (3,000,000 ticks) are compared by their words starting
  inside the overlap, tokenised by `FillerWords.normalized` with empties dropped; with at least one
  token on each side and a longest common subsequence of at least 0.6 × the shorter side they are
  named in a note, clip ids ascending, one note per pair: "Clips 3 and 7 carry the same speech. Mute
  one, or switch its audio off, to read it once." Nothing is hidden.
- **TX-11 — A word is shown but not editable when cutting it would break something**, and the
  first rule that applies is its `why`: inside a nest ("Inside nest <name>: open it (⌘↓) to cut its
  words.", naming the OUTERMOST enclosing nest); under a transition ("Under a transition: a cut here
  would leave one clip's tail under its neighbour.", when the word's `[start, max(end, start + 1))`
  meets a `SilenceDetector.overlapWalls(snapshot)` wall of the container); on a locked track
  ("Track <name> is locked: a cut would leave these words in place and move everything after
  them.", the word's container track). A ramped clip's words are editable (SR-18 (e)).
- **TX-12 — The fill reads each heard media once, whole, on this Mac, and keeps it in TR-14's cache
  (amends TR-14).** It runs only when a tool needs words (and, from TX2a, while the Transcript tab
  shows), never at import. It reads each heard media with no cloud transcript serving `.captions`
  and no stored run covering the whole file as ONE run, a `Transcriber.Job` from tick 0 for the
  media's duration at speed 1 (clip 0), through `TranscriptReader.recognize`, then
  `DeviceTranscriptCache.Heard(runs:over:)` and `store` — only when the run was not cancelled and
  the file's stamp did not change during it. A hit is `DeviceTranscriptCache.lookup` of that whole
  job (a cache hit needs one stored run containing the asked span and runs never merge, so a
  played-span read would re-read on any growth). `TranscriptFill` is one per document (keyed by its
  `recipeKey`, dropped when the document is no longer open for analysis): owners each want a list
  of items (`want` replaces that owner's list), `release` withdraws only its caller's want, an item
  no owner wants is cancelled through its `Transcriber.CancelToken`, `wait` blocks off main until
  the owner's items settle, and `progress` answers the running media's fraction. One media at a
  time, on one serial `.userInitiated` queue, off main: the media under the playhead first, then by
  first instance start. **TX-S1's verdict (2026-11-01, OS build 25F80, Apple M2 Max, 12 cores, 96
  GiB, on AC; three lanes sharing the machine, load average about 14):** a 3,600 s file of `say`
  phrases recognised whole twice in 40.7 s and 40.8 s (judged on the slower: 0.68 s per minute of
  speech, rule ≤ 360 s), peak added `phys_footprint` 16.3 MB (rule ≤ 1/32 of physical memory,
  3.22 GB; the recogniser's own service process is not counted), a 115 MB temporary WAV, 10,225
  words; 600 s in 7.3 s; the six 600 s windows of the same audio matched 10,119 words with median
  |Δ start| 0.00 s and p95 0.18 s; S-TH1 and S-LONG1 do not exist yet and are owed. **Outcome A**:
  one whole-file run per media. `play_preview` over 10 s of a 1080p timeline in the Release app
  composed 300 frames idle (median of 3), 300 while a sibling process recognised the 3,600 s file at
  default QoS and 300 under `taskpolicy -c utility` (100 % of idle; a sibling process's reading, the
  fill not yet built): the fill keeps **`.userInitiated`**, so `SpeechEngine.swift` pays no toll and
  takes no priority argument. The language is the Mac's unless chosen (a separate cache file). The
  measured rate replaces "a few seconds per minute" in the guide. TR-14's line: "**Amended
  2026-11-01, by TX-12:** the Transcript tab, `get_timeline_transcript` and `review_transcript` also
  read this cache, and the tab's fill stores one run per media over the whole file. Captions,
  Remove Filler Words, `detect_fillers` and `transcribe_for_fillers` still never read it (TR-7)."
- **TX-13 — `get_timeline_transcript {from?, to?, tracks?, language?}`**, an app-state read with no
  `scope`: off main, the assistant's Stop reaches its fill, never the network, no AI-7 row, no undo
  step. One main-thread hop reads the document, the edited container's plan and snapshot, the
  arguments (`from`/`to` through `optionalTimeArg`; `tracks` through `intsArg`, each id checked
  against the call's id scope and refused with `noSuchId("track", id)`), the instances and
  `no_words`, and each heard media's cached transcript; then the language's spelling is checked,
  and the installed model asked only when a heard media has no cloud transcript. The fill runs what
  the window needs — the media of the instances meeting the window — as this call's want, released
  when the call ends or Stop withdraws it. `words[]` carry `text`, `start`, `end`, `clip`, `track`,
  `media`, `engine`, `filler`, `speaker` when known, `editable`, `why` when not editable, and `id
  {nest_path, media, source, k}`; `media[]` carries each heard media's `engine`, `language` (a
  cloud transcript's own code when it has one) and `fillers_reported`; `no_words[]`, `notes[]`,
  `count` (the words answered), `project`. **The window** is TR-13's: snapped, the overlap rule (a
  word across an edge answered whole), `to` not after `from` refused as `.empty`, then clamped to
  `[0, container duration)`; nothing left is refused: "The window <bounds> is outside the timeline,
  which runs from 0 to <D> ticks." `from`/`to` are echoed when given. `tracks` keeps the words on
  those container tracks. **Paging:** a page is the first 2,000 windowed words; when more follow,
  `truncated: true` and `next_from` = `frameFloor(the next word's start)` (the largest frame
  boundary at or before it, `ReelTime.snapToFrame`, so `optionalTimeArg`'s nearest-frame snap
  returns it unchanged). The page is cut back until `frameFloor(next.start) > frameFloor(last
  kept.start)`; if that empties it, the page stays whole and `next_from` is the frame boundary after
  its last word's frame. Passing `next_from` back drops no word; a word overlapping it may reappear
  with the same `id`. Notes carry TR-11's filler sentence once when any heard media has
  `fillers_reported` false, and the same-speech notes. A failed fill refuses the call with the
  recogniser's sentence; a cancelled one answers "The transcription was cancelled." `get_transcript`
  stays one clip (TR-11…TR-14).
- **TX-14 — This bet applies CJ-3 through `ModelKeys` and adds no key rule of its own.** The
  transcript, cuts, restore, pauses and retakes need no key; filler strikes read any media whose
  AssemblyAI transcript serves `.fillers`, key or no key; Transcribe… (which uploads) is offered
  only with the key; the Fillers box is disabled only on CJ-12's condition; the hand-off is keyed
  as CJ-12's Assistant row. `get_timeline_transcript` sends nothing, so it has no `ModelKeys.keyed`
  row.

CU-33 and CU-37 are CU3a2's (the cursor drawn in its clip's layer, and files that wait for it),
recorded before its code. No core, FFI or format change; the `LayerUniforms` block's size is
provisional by landing order (CJ-8 (b)), the integrator renumbering it when CO2a2's group lands
first.

- **CU-33 — The cursor composited inside `layerSample`, before the grade, at `texture(5)`
  (CU3a2).** (a) Order: texel, un-premultiply, ripples (oldest first), sprite, then `gradeSample`;
  all behind `cursorEnabled > 0.5`; never on a slate. (b) Space: source display px, `uv ×
  (sourceWidth, sourceHeight)`, before `orientedUV`; `state`'s movie px are taken unrotated (a
  cursor file belongs to a screen recording). Rect = (x − hot_x, y − hot_y, w, h) from `state` (px
  at `scale`), sampled with the layer's sampler; outside it nothing. **Per source texel** (found
  while building, CU3a2): a sample within 2 px of the sprite's rect or a ripple's ring reads its
  bilinear footprint's four texels, each at its centre with the cursor laid over it there, and
  weights them as the sampler does, so a sample between texels — a zoom, a blur's tap, a region's
  re-sample — reads what it would read from a pointer burned into the picture; every other sample
  is the one sample it was. Composited per sample instead, a blurred clip differed from a burned
  pointer by up to 10/255 at the sprite's edge (L8's first run). (c) Sprite: premultiplied, ×
  `opacity` (o): a′ = s.a·o + a(1 − s.a·o), rgb′ = (s.rgb·o + rgb·a(1 − s.a·o)) / max(a′, 1e-4).
  Drawn when `props.show`, `visible`, `image` non-null and `style == recorded`; `arrow` and a null
  image draw no sprite until CU4 (CU-41). (d) Ripples: `state.ripples` (≤ 4, only under `clicks:
  ripple`); R = 24 pt × `click_size` × `px_per_point`; radius R·(1 − (1 − phase)²), ring width
  R/8, 1-px antialias (coverage `saturate(R/16 + 0.5 − |d − r|)`), alpha `click_color.a × (1 −
  phase)`; colour the recipe's normalised `#rrggbb[aa]`, an unreadable one `#ffffffcc`. (e) HLG:
  sprite through `MetalRenderer.lifted` (`LayerLift`), ripple RGB through
  `InputConversions.liftSDR`; SDR untouched. (f) `at`: `RecipeCursor.at` forward; when `reversed`,
  the forward stamp of the frame shown: `max(0, ReverseMirror.mirrored(at, about: pivot) −
  frame)` (`CursorFile.pivot`, `.frame`), pivot the media's model duration. (`ReverseRenderer`
  writes the frame shown from p until p′ at T − p′, so plain `pivot − at` is the next frame's time
  at every frame time; less one frame lands on p for a constant-rate source, and on a
  variable-rate one within a frame, as forward playback already is.) (g) Texture 5 is bound on
  every draw through the layer fragments (`drawLayer` with its reflection, `shadowSilhouette`),
  `placeholder` when no sprite; a sprite is made once per image, never per frame. (h) A layer with
  no cursor draws byte-identically to before (CU-35).
- **CU-37 — A track not ready yet, and a file that fails (CU3a2).** (a) The preview's key
  publishes its cursor files and wants their tracks at each clip's base smoothing
  (`RecipeSource.setMediaURLs`); the compositor draws only a `ready` track and otherwise draws
  without; `.cursorTrackDidLand` refreshes a paused editor frame. (b) An export waits before its
  build for every clip's tracks (whole project); `renderFrameReported` (`render_frame`, Save
  Frame, the eyedropper, image sequences, look thumbnails) waits for the tracks its frame's recipe
  names. (c) A failed track — the core's sentence, or `CursorTracks`' "the cursor file P could not
  be read" — is one `ExportCursorWarning` per media; the clip draws without a cursor and nothing
  fails. `export_status`'s `done` answer carries them as `cursor_warnings [{media, path,
  message}]`, absent when none (G-24 (c)'s shape), and `render_frame` adds "The cursor of media M
  is not drawn: \<message\>." per warning. (d) A key that never publishes cursor files
  (thumbnails, analysis, processed loudness) draws no cursor. (e) `RecipeSource.unregister`
  releases the key's `CursorTracks` owner on `DispatchQueue.global(qos: .utility)`, never on the
  caller's thread, because `Exporter.deinit` can run inside `CursorTracks.wait`'s `cancelled()`
  under the registry's lock; keys are never reused, so a late release drops no newer want.
