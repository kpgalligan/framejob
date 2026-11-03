# Spec §11 — decisions: Creator jobs, the pause token onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md),
[`creator-jobs-4.md`](creator-jobs-4.md) and [`creator-jobs-5.md`](creator-jobs-5.md) (CJ-, VR-,
TX-, SW-, CU- and CO-), so a citation never has to say which file; `creator-jobs.md` says what the
road map builds and how its IDs are made (CJ-7). This file is new because `creator-jobs-5.md`
would pass the road map's ~500-line split rule with TX3b's entry (468 lines, 2026-11-02); each
phase's decisions are appended here from now on, before its code. The series continues in
[`creator-jobs-7.md`](creator-jobs-7.md) from FC3's FC-30.

## TX3b — the pause token (2026-11-02)

TX-34 is TX3b's (the pause token, split off TX3 by size), recorded before its code; it is the
number TX3a's TX-30 reserved for it. The owner's answers that set it: 2026-11-01 for TX6 — a long
pause is over 1.0 s, and 0.2 s is kept: **yes**; 2026-11-02, answering TX3b's first attempt's
STOP — "Fix word starts first": TX1b (TX-15…TX-19) moves on-device word starts to their sound,
and TX3b keeps its no-sliver clamp (that STOP's option (a)): no two-range cut and no one-frame
slivers. Nothing here sends anything: no `ModelKeys` row (CJ-3). No core, FFI, op, format or
product-tool change; only the dev tool `transcript_view` gains an argument.

- **TX-34 — A pause over 1 s between two words of one clip is a token, and deleting it keeps 0.2 s
  each end.** It amends TX-30's pause clause (both ends of a pause are read from the voice cache,
  not from word onsets) and TX-23 (`select_pause`), and adds `pauses[]` to TX-33's answer, not to
  its prompt paragraph (TX5–TX7 amend that).
  - **Detection** (`TranscriptCut+Pause.swift`, `pauses`, pure). For each pair of consecutive
    shown tokens a, b: both editable, in ONE instance (candidates keyed by clip id and
    `segment.path.dropLast()`, the first whose segment holds the word's start, else the first —
    `edges`' rule, so one instance is one clip, one nest path and one media), the media's words
    and voice cache in the table's context (no cache: no pause). a's and b's source words `aw`,
    `bw` are each the media's first word whose `identityTick` is the token's `id.source` (TX-17:
    an on-device word's `source` is its moved start).
  - **The window** is `W = [max(aw.source, aw.sourceEnd, job.sourceIn), min(max(bw.source,
    bw.sourceEnd), job.sourceIn + job.sourceLength))` in source ticks. It opens at a's END, so one
    silence makes one pause and the silence before a is never shown again after it. In W the
    longest run of cells wholly inside it with `speech[k] < defaultVoiceConfidence` (cell k
    `[k·chunkTicks, (k+1)·chunkTicks)`), the earliest of equal runs, is `[r0, r1)`.
  - **The run is extended back** (`quietStart`): `r0' = r0` stepped back one cell while cell
    `k − 1` is non-speech and `(k − 1)·chunkTicks ≥ max(aw.source, job.sourceIn)`. Word ends are
    not moved (TX-19), and TX1b's O7 measured "dog" ending 227.5 ms and "jugs" 168.7 ms past their
    phrases, so a window opened at the recognised end starts late; the extension starts the span
    where the speech ends, and its floor at a's (moved) start keeps the silence before a out.
  - **The span** is `[project(r0'), project(r1))` (`MediaTranscript.project(_:in: job)`), plus a
    nested segment's shift as in `edges`. It is a pause only when longer than
    `pauseLongerThan` (1 s) of TIMELINE time: a ×2 clip's 1.5 s source silence is no pause.
  - **Its cut.** `s = max(0, snapToFrame(span.start + 0.2 s))`, `e = max(0, snapToFrame(span.end −
    0.2 s))`. When b's timeline start lies in `[s, e)`, `s` moves to the first frame boundary
    after it, so no word's start is cut and no word leaves the transcript; no two-range cut is
    made. Under TX1b b's start sits within one voice cell of `span.end`, so this clamp no longer
    fires on a real gap; it stays as the guard. The pause is dropped when `e ≤ s`; when another
    shown token's TX-32 extent meets `[s, e)` (the latest extent end before a, the earliest onset
    after b); or when an unread clip's start lies in `[s, e)`. a's own recognised end may lie
    inside the cut: a word is placed by its start (TX-10), and its end is not moved (TX-19).
  - **Refusals, in order** (`planPause`): a read word on a locked track (every track) whose
    `[start, max(end, start + 1))` meets the cut, in TX-32's sentence; then the PEAK clip count
    past `RC_MAX_CLIPS`, in TX-32's sentence. Counted by TX-32's `clipsAfter` and `clipsPeak`.
  - **The tab.** The pane computes the pauses once per rebuild, from `cutTable()`, and shows each
    as " [x.x s]" (the span, one decimal) in `DS.textMuted` after token a. A click selects it (the
    word selection cleared; the two are exclusive), its cut becomes the in/out range through
    `set_range`'s door, and the playhead seeks to the cut's start, as a word click seeks to its
    word. ⌫, ⌦, Edit ▸ Delete and Edit ▸ Ripple Delete then send one `ripple_delete_ranges` of the
    cut, the undo step **"Delete Pause"**; a refusal shows at the inspector's foot (CI-10). Esc
    clears it; ← and → move from a; a drag, ⇧-click, ⇧-arrows and ⌘A select words only (a word run
    spanning a pause already cuts it). A rebuild re-maps a selected pause by the identities of a
    and b and re-plans it while the document's range is still the one it set (TX-31's rule), with
    no seek.
  - **A voice cache landing** under a shown media (a `speech` post of `.mediaCacheDidChange`)
    remakes the tab's table and pauses (`source.update()` after TX-18's re-read), so a
    cloud-transcribed media's tokens appear without another edit. A voice cache REPLACED under a
    shown cloud-transcribed media keeps the old one in the tab's table until the tab shows again,
    as TX3a's word cuts do (filed).
  - **The agent.** `get_timeline_transcript` answers `pauses: [{start, end, cut_start, cut_end,
    clip, track, media, follows, precedes}]` from the same table as the words' cuts (`start`/`end`
    the span; `follows`/`precedes` the `{nest_path, media, source, k}` ids of a and b), one row
    per pause whose `follows` word is in the answered page; an agent shortens one with one
    `ripple_delete_ranges [[cut_start, cut_end]]`. The dev tool `transcript_view` takes
    `select_pause` (an integer ≥ 0, a click on pause i as a person makes it) and answers `pauses:
    [{index, after, start, end, cut_start, cut_end}]`, `pause_selection` and, with a pause
    selected, `cut: {pause, start, end, clips_after, clips_peak, refusal}`; it refuses "select_pause
    names pause <i>; the tab shows <n>." and "select, click and select_pause each set the
    selection: pass one.", and `select_pause` with `words_from` or `language` as TX-27 refuses
    `select` and `click` (a rebuilt tab would click another pause), its sentence now "select,
    click and select_pause name tokens of the view as it is; set words_from or language in a
    call of their own."
  - **The proof** (`transcript_cut_proof.py`): probe rows U7 (detection, including moved starts,
    the back extension and its floor), U8 (the cut) and U9 (the plan); app rows P1–P4 on
    `pause_fixture` (`say` phrases joined by 2.5 s, 1.5 s and 0.5 s of zeros); ten mutants. JOB-11
    is the person's check.

## CU4 — the Cursor section (2026-11-02)

Recorded before the code. CU-40…CU-43 are CU4's: the Picture sub-tab's Cursor section grows from
Show cursor to every `video.cursor` key (CU-30), `style: arrow` and a frame with no recorded image
draw Frame Job's own arrow, and the look a recording lands with is settled. No core source, FFI,
format (41 stands), op, tool, `LayerUniforms` or shader change; the arrow uses the sprite slots
and `texture(5)` CU-33 laid down. Nothing here sends anything anywhere, so nothing is keyed
(CJ-3). The owner's answer (2026-11-01): a recording lands with its cursor as captured, plus
ripples when Show Clicks was on.

- **CU-40 — The Cursor section's rows, in order, and how each routes.** Id `video.cursor`, title
  "Cursor", after Background and before Shadow, closed by default (CU-38 (b)'s gate and place,
  unchanged). Each row has its own undo name:
  - Show cursor: checkbox, "Show Cursor".
  - Size: value row 25–800 %, slider to 400 %, quick 50/100/150/200/400; writes `scale` = v/100;
    "Cursor Size".
  - Style: popup As recorded / Arrow; "Cursor Style".
  - Smoothing: popup Off 0 · Light 0.25 · Medium 0.5 · Strong 1 (`CursorProps.smoothingSteps`);
    "Cursor Smoothing".
  - Hide when idle: popup Never (null) · 1 s · 2 s · 3 s · 5 s · 10 s
    (`CursorProps.hideIdleSteps`); "Hide Cursor When Idle".
  - Clicks: popup None / Ripple; "Cursor Clicks".
  - Ripple color: a colour row, discrete ("at end" when keyed); "Ripple Color".
  - Ripple size: 25–400 %, quick 50/100/150/200; writes `click_size` = v/100; "Ripple Size".
  - A button row: **Polish** writes `{smoothing: 0.5, hide_idle: 3}` (`CursorProps.polished`),
    "Polish Cursor", its tooltip "Smoothing Medium and Hide when idle after 3 s".
  - **(a) Writes.** Each row writes only its own key through `VideoPatch(cursorPart:)`
    (`CursorPatch`, all eight keys optional, `hide_idle`'s null written as `NSNull`). Reset
    writes all eight defaults as one `cursorPart`, "Reset Cursor".
  - **(b) Reads.** Ripple color and Ripple size are enabled only while Clicks reads Ripple.
    Smoothing and Hide when idle READ the clip's BASE `video.cursor` (0 and null when it has
    none; the defaults under `.defaults`), never the evaluated props: `clip_state` does not apply
    `with_base_cursor`, so an evaluated smoothing can be an end's no-op value. A stored value
    matching no step shows a blank popup with nothing checked; their mixed test compares the
    clips' base values. Colour reads `ReelColor.normalise(click_color)` then
    `GraphicSchemaRows.rgba(css:)`, and writes `GraphicSchemaRows.css(_:)`.
  - **(c) Summary.** "off" when `show` is false and `clicks` none; else "on" ("arrow" when
    `style` is arrow), plus " + ripples" when `clicks` is ripple.
  - **(d) Routing inside an action** (`InspectorBinding.structural(video:for:)`). Size and Ripple
    size animate; Show, Style, Clicks and Ripple color switch at the action's end (CU-30); Smoothing,
    Hide when idle and Polish are the clip's, ⊘ inside an action. Two independent rules split a
    `cursorPart` into `own` (smoothing, hide_idle) and `end` (the other six): **(1)** a non-empty
    `own` goes to the base and only `end` stays in the end, an empty end dropped; **(2)** a
    non-empty `end` on a clip with no BASE `video.cursor` also stores the whole defaults cursor on
    the base, merged with `own`, in the same step — so Size animates rather than switching
    (CU-30: an end over no cursor switches). With (1) and not (2) the base gets `cursorPart =
    own`; with neither, no cursor key.
- **CU-41 — The Arrow: Frame Job's own vector arrow.** One path in a 14 × 21 pt box, tip (the hot
  spot) at (1.5, 1.5): `M1.5 1.5 L1.5 17 L5.3 13.4 L7.9 19.4 L10.6 18.3 L8.1 12.4 L13 12.4 Z`,
  fill `#000`, stroke `#fff` 1.25 with round joins (`CursorArrow`); no Apple artwork (CU-8).
  Rasterized by the graphic engine (`GraphicLibrary.rasterize`) at W × H = max(1, round(14·k)) ×
  max(1, round(21·k)), k = `px_per_point` × `scale`, through a library `CursorSprites` owns; one
  texture per pixel size and output in a second LRU of 64, never one per frame at a fixed size,
  lifted in HLG as a sprite is (CU-33 (e)); `uploads` counts it. Drawn 1:1 at (x − 1.5·W/14, y −
  1.5·H/21, W, H) with the sprite's opacity, for `style: arrow`, and for `recorded` whenever
  `state.image` is null (`cursor_image: none`, CU-6's fallback) or its texture cannot be made;
  only inside `props.show && state.visible`, ripples unaffected. It is drawn at its own size ×
  `px_per_point` × `scale`, NOT at the recorded image's size, deviating from the road map's "at
  the image's size": a recorded image's size changes with the cursor kind, and CU-11 records
  none. **Amends CU-33 (c):** "Drawn when `props.show` and `visible`: the recorded image when
  `style == recorded`, `image` non-null and its texture made, Frame Job's arrow otherwise
  (CU-41)."
- **CU-42 — The look a recording lands with (owner, 2026-11-01).** As captured: no `video.cursor`
  is written at landing except `{clicks: "ripple"}` on its screen clips, and only when Show Clicks
  was on and the file is not in the picture. That write is CU3c's, inside the landing's grouped
  edit with its B3 row; until CU3c every landed file is `in_picture: true`, so CU4 writes nothing
  at landing. The polished look (Smoothing Medium, Hide after 3 s) is one click — **Polish** — or
  CU10's landing option, never a silent default.
- **CU-43 — CU4's proof.** `cursor_layer_proof.py` on a 640 × 360 canvas over `clean.mov`, bounds
  the bbox of pixels more than 8/255 from the `show: false` render: S1 (probe) each row's control
  outside an action commits one named step whose one op is `set_video {cursor: {<its key>: v}}`
  (Size 200 → 2, Arrow, Medium 0.5, 3 s → 3 and Never → null, Ripple, a colour's CSS, Ripple size
  150 → 1.5, Polish → `{smoothing: 0.5, hide_idle: 3}`); S2 `scale` 2 against 1 doubles the
  bounds ±1 px for the recorded 12 × 16 sprite and for the arrow, whose bounds at 1 are 13–15 ×
  19–21 px; S3 the probe's `cursor_idle.fjcursor` (a zig-zag at k 0–29, still from k 30 to 104,
  moving from k 105; clicks at k 9 and 20): with `hide_idle` 2 frames 99 and 100 byte-identical to
  `show: false` and frame 101 equal to `hide_idle` null; S4 the same file at `smoothing` 1: the tip
  within 0.5 px of the click position at frames 9 and 20, more than 2 px from the raw tip at 15;
  S5 (probe) inside an action Smoothing Strong and Hide 2 s commit only a base `set_video` and
  their gutters are ⊘, Size 200 only `set_action_end {video: {cursor: {scale: 2}}}`, and on a clip
  with no base cursor the base defaults plus that end, `props.scale` strictly between 1 and 2
  mid-action; S6 `cursor_none.fjcursor` (`cursor_image: none`): `recorded` byte-identical to
  `arrow` at three frames and not to `show: false`; S7 (probe) `CursorSprites.arrow`: 14 × 21 twice
  one upload, 28 × 42 one more, the sizes as asked, a fill texel opaque and dark, texel (12, 2)
  transparent. Seven mutants: smoothing and hide_idle routed into the end, the base defaults
  skipped (S5); Size writing `click_size` (S1); Arrow ignored (S2); the null-image fallback removed
  (S6); an arrow made per frame (S7). Person check JOB-22.

## CU5 — cursor data travels (2026-11-02)

Recorded before the code. CU-50…CU-55 are CU5's: a recording's cursor file goes where its movie
goes (Consolidate Media copies it into `media/`, an open re-anchors it), the Media tab names it
and offers Locate… and Remove through the new op `set_media_cursor`, and agents read the file's
events through `get_cursor_events`. No format change (41 stands), no `rc_*` export, no
`LayerUniforms` or shader change; the FFI's `ReelCursor` and `CursorValues`' `events`/`path` are
reused. Nothing here sends anything anywhere, so nothing is keyed (CJ-3). The road map asked for
no owner question at this phase.

- **CU-50 — `set_media_cursor {media, cursor}`, document-level.** `cursor` is `{path, bookmark?,
  in_picture}` or `null`. Refused inside a scope ("set_media_cursor has no meaning inside nest N",
  `scope.rs`'s `refused_inside`, beside `set_media_speech`) and listed in
  `ReelOp.documentLevelNames` (eleven names). `cursor` is read strictly, as `media_color.rs` reads
  `color`: neither an object nor `null` → `Err` "cursor must be a json object or null, not …"; a
  key other than `path`, `bookmark` and `in_picture` → `Err` `unknown key "k" in cursor`; a miss
  against the record's shape (`in_picture` absent, a path that is not a string) → `Err` "cursor
  does not match the schema: …"; an unknown media → `Err`. `null` clears (an identity when there
  is none); a value equal to the stored one is an identity; otherwise `cursor_props.rs`'s
  `check_media_cursor` sentences — an empty path, a media that is not a video with a picture —
  are refusals. The value is stored as given; the core makes no `movie_size` check (it opens no
  file). `media_cursor.rs` holds it.
  - **(b) The tool checks as Locate… does.** For a non-null `cursor` the `set_media_cursor`
    handler resolves the media (an unknown one goes on to the op's own `Err`), runs
    `MediaImporter.cursorAttachment(at:to:)` against the media's descriptor before applying, and
    refuses with the problem's sentence (CU-34: unreadable, refused by `ReelCursor`, no picture,
    a `movie_size` not the movie's); then refuses an `in_picture` that is not the file header's:
    "The cursor file <name> was not attached: its in_picture is <h> and the call says <c>."
    Passing both, the op is applied with the caller's value as given (a bookmark only when
    given). `null` is not checked. Consolidate and the re-anchor apply the op through the document
    unchecked: their file is the attached one, copied.
- **CU-51 — Consolidate's second copy, and its order.** For each media with a `cursor`, after its
  movie is planned: a file at `cursorURL(for:)` that does not exist → `missingCursors` (the
  summary says "N cursor file(s) were missing and left alone."); a file already inside `media/`
  with a bookmark or a differently spelled path → a `cursorRelinks` entry; else a copy named
  `<stem of the movie's destination, or its in-package URL>.fjcursor`, claimed by the movie
  rule (case-insensitive, `-2` suffixes). Two media whose cursors resolve to one file share one
  copy (`cursorAliases`). The run: the movies' relinks and copies first, unchanged; then each
  cursor copy, only when its movie copy is nil or on disk; then `set_media_cursor {path:
  destination, in_picture}` (no bookmark) only after that copy succeeded. A failed cursor copy is
  a `failures` line and leaves `media.cursor` at the original. An alias is set only once its
  destination exists. Cancel is checked between cursor copies. Cursor files count in `copied`,
  `bytes` and `isEmpty`. CU-39 holds: Consolidate's `relink_media` ops are unchanged and carry no
  probe, so they keep `media.cursor`.
- **CU-52 — The open-time re-anchor.** For each media with a `cursor` whose `cursorURL(for:)`
  file does not exist while `<package>/media/<last component of cursor.path>` does, the open
  applies `set_media_cursor {path: candidate, in_picture}`, purely, as
  `reanchoringConsolidatedMedia` is applied (`reanchoringCursorFiles`). It runs inside
  `repairingMedia`, after the media re-anchor and before the re-copy; `ProjectDocument.swift`
  takes no line.
- **CU-53 — `get_cursor_events`.** Arguments `{media | clip, from?, to?, kinds?, smoothing?}`;
  the answer `{ok, media, clip?, time: "media"|"clip", from, to, size: [w, h], cursor_file,
  in_picture, clicks?: [{t, button, down, count, x, y, q?: [qx, qy]}], scrolls?: [{t, x, y, dx,
  dy, q?}], shortcuts?: [{t, keys, code}], typing?: [{from, to, marks}], path?: {smoothing, t,
  x, y}, count, next?, project}`.
  - **(a) Arguments.** Exactly one of `media` and `clip`. `kinds` ⊆ clicks, scrolls, shortcuts,
    typing, path; the default is the four without `path`. `smoothing` 0–1, read only with `path`;
    its default the clip's base `video.cursor.smoothing`, else 0.
  - **(b) Time.** Media time is forward source ticks, default `[0, duration)`. Clip time is clip
    ticks, default `[0, duration)`, mapped to source through `SourceMap.source(atClip:)` on a
    ramp, else `in + t × speed`; each event comes back through
    `AnalysisClipTimes.clipTime(ofSource:)` and is kept only inside `[from, to)`.
  - **(c) Q.** For clicks and scrolls in clip time only: `q = (x − W/2 − (l − r)/2, y − H/2 −
    (t − b)/2)`, W × H the media's size in source pixels, the crop the clip's base crop when it
    has no actions, else `clipState` at `clip.start + t` on the edited project — the region frame
    `add_zoom_action` takes.
  - **(d) The path.** Sampled every 60,000 source ticks (the core's 10 Hz bound) at the asked
    smoothing.
  - **(e) Paging.** The events of every asked kind and the path samples are merged by time; a
    page holds at most 5,000; `next` is the first time left out, and the page holds only times
    `< next` (all at one tick are kept together); a typing stretch across `next` is in both pages.
    Scrolls are the core's single events; scroll bursts are CU7's (`cursor_bursts.rs`).
  - **(f) No `scope` argument.** Like `get_media_analysis`, the clip is looked up in the container
    `set_scope` has open (the call's `scope` is read only for op tools, `AgentServer.swift`
    frozen). This deviates from the road map's "`scope` declared".
  - **(g) Refusals, in order.** One of media and clip; `kinds`; `smoothing`; an unknown id; not a
    media clip; a clip that plays reversed ("Clip C plays reversed; get_cursor_events reads only
    clips that play forward. Ask with media M for the file's own times.", CU-5); no cursor file;
    the file missing (naming Locate… and `set_media_cursor`); `to` ≤ `from`; the core's open
    sentence.
  - **(h) Threads.** Off main: one main hop resolves the media, clip and file; the file is opened
    as a fresh `ReelCursor` off main; a last main hop computes Q and the answer.
- **CU-54 — The Media tab's Cursor section.** Id `media.cursor`, title "Cursor", after Camera Log
  and HDR10, shown whenever the project has a video media with a picture (so Locate… stays
  reachable after the last Remove), acting on the selected media. A readout: "Select a video in
  the list", "No cursor file", "<file name>", "<file name> — missing". **Locate…** (enabled on a
  video with a picture) opens an `NSOpenPanel` of `.fjcursor` files, runs
  `MediaImporter.cursorAttachment(at:to:)`, and on success applies one step "Locate Cursor File";
  on failure an `NSAlert` sheet says the problem's sentence and nothing is edited. **Remove**
  (enabled with a cursor) applies `set_media_cursor` with `null`, "Remove Cursor File". The
  summary is the file name, or "missing". The tool's undo names are the same two.
- **CU-55 — CU5's proof.** `cu5_proof.py` on its own instance, a scratch HOME, `A.mov` copied
  and a v1 cursor file written in Python with A.mov's `movie_size` and `in_picture: false`: M1
  Consolidate puts the movie and the `.fjcursor` in `media/`, both paths inside the package, no
  bookmark; M2 the package moved, the originals removed and reopened: both re-anchored and a
  cursor frame byte-equal to before Consolidate; M3 (probe) `cursorLine`'s four strings, the
  section present iff a media is a video with a picture, Locate's attach refusing a wrong
  `movie_size`; M4 a fixture with crop `{l: 40, t: 20}`: counts, `x`/`y` and Q equal the
  fixture's arithmetic, `path` equal to CU2's T4 run within 1e-9 px; M5 a cursor file at mode
  000: the movie relinked, `media.cursor.path` still the original, a failure line; M6
  `set_media_cursor` with a `scope` refused; M7 a reversed clip refused by name while `{media}`
  answers; M8 5,003 clicks paged 5,000 then 3 with `next`; M9 the tool refusing a wrong
  `movie_size` and a differing `in_picture`, each in its sentence, `media.cursor` unchanged, and
  the matching file applied. Seven mutants: the op emitted before the copy lands (M5); the
  re-anchor not run (M2); Q without the crop (M4); `SetMediaCursor` out of `refused_inside` (M6);
  the reversed refusal removed (M7); the page cap not applied (M8); the tool's attach check
  removed (M9). No person check: the road map names none.

## CU6 — record shortcuts (2026-11-02)

Recorded before the code. CU-60…CU-63 are CU6's: a **Record shortcuts** box in the recorder
panel (off by default) makes a display, window or picked recording write each shortcut, spelled,
and a time-only mark for every other key-down into each segment's cursor file, through a
listen-only CGEventTap under Input Monitoring (CU-S1 `keys=tap`, `grant_api=cg`). No FFI, op,
format (41 stands) or cursor-file version change: `keys` was defined in v1 and empty in every file
until now, so the core's one change, CU-60's ⌥ arm in the shortcut check, refuses nothing a
written file held. Nothing here sends anything anywhere, so nothing is keyed (CJ-3). The owner's
answers (2026-11-01): "The indicator is a keyboard mark plus a menu row." and, minor (taken as
recommended), "⌥ with arrows, delete, return, tab or escape counts as a shortcut."

- **CU-60 — Which key-down is a shortcut, and how it is spelled.** It amends CU-7 (the ⌥ arm) and
  CU-10's shortcut check. `CursorKeyFilter.swift` (pure) decides each key-down, in this order:
  (a) secure input held by any process (`IsSecureEventInputEnabled()`, read at delivery) →
  nothing, not even a time; (b) an auto-repeat → a typed mark; (c) ⌘ or ⌃ held, or ⌥ held with
  the key code one of ← → ↓ ↑ (123–126), Delete (51), Forward Delete (117), Return (36), keypad
  Enter (76), Tab (48) or Esc (53) → a shortcut; (d) every other key-down → a typed mark. ⇧ alone
  never makes a shortcut, and neither does ⌥ with any other key (⌥E types é). **Spelling:** the
  held modifiers in the order `cmd`, `ctrl`, `opt`, `shift`, then the key: a named key by its
  virtual key code (`return`, `enter`, `tab`, `space`, `delete`, `forwarddelete`, `esc`, `left`,
  `right`, `down`, `up`, `home`, `end`, `pageup`, `pagedown`, `help`, `f1`…`f20` by their kVK
  codes), else the layout's character with no modifier applied
  (`NSEvent(cgEvent:)?.characters(byApplyingModifiers: [])`) lowercased, `+` spelled `plus`, and
  an empty, whitespace or control character `key<code>`; joined by `+`. `code` is the virtual key
  code. **A typed key's character is never read**: the tap asks for a character only for a
  key-down that is a shortcut and not under secure input, and a typed mark is its time alone.
  A key-down while the recording is paused (no open segment) is dropped. **The core's check**
  (`cursor_file_check.rs`) accepts a shortcut holding `cmd` or `ctrl`, or holding `opt` with its
  LAST token one of `OPTION_SHORTCUT_KEYS` (`left`, `right`, `up`, `down`, `delete`,
  `forwarddelete`, `return`, `enter`, `tab`, `esc`); otherwise "it holds neither cmd nor ctrl, nor
  opt with left, right, up, down, delete, forwarddelete, return, enter, tab or esc". A `typed`
  entry with any key but `t` is still refused (`check_typed`).
- **CU-61 — The indicator (owner: a keyboard mark plus a menu row).** While a recording's key tap
  exists (`ScreenRecorder.recordsKeys`), its status item's title is the dot or ❚❚, then a space and
  `⌨︎` (U+2328 with the text presentation selector) in the menu bar's own colour, then the time; its
  menu's first row is a disabled "Recording keyboard shortcuts" and a separator, recording or
  paused. The item's length is fixed per item for the marks it shows (`itemLength(keys:)`, the
  widest title at 9:59:59 for either mark, plus the insets), so a recording without shortcuts keeps
  today's length, title and menu exactly. Both constructions — the panel's and the tool's chrome —
  pass `keys:` from `recordsKeys`. It amends the voice-over bullet's status item (spec §9 row 39).
- **CU-62 — The grant: when it is read, asked and refused.** Input Monitoring is read by
  `CGPreflightListenEventAccess()` and asked by `CGRequestListenEventAccess()`. **The panel** reads it
  only when Record shortcuts is on with a screen source (the box is greyed, and `keys` is `off`,
  for Microphone Only and Camera); a press's order is Screen Recording → Input Monitoring → Camera
  (beside the screen) → Microphone. Its step is `screenStep`'s table (granted goes on; a shell
  launch always asks; a launchd launch asks once, remembered in `FrameJobInputMonitoringAsked`, then
  opens the pane). Because CU0b measured that no prompt shows and Frame Job is not listed until
  added by hand, an ask ALSO opens System Settings at `Privacy_ListenEvent`; the note is "Input
  Monitoring is not granted to Frame Job. Turn it on in System Settings ▸ Privacy & Security ▸
  Input Monitoring. If Frame Job is not in its list, add it with +." plus " System Settings is open
  at that pane." when it opened, plus `launchClause`. No "then relaunch" (CU0b: not needed). The
  panel steps aside for System UI before asking or opening, as for Screen Recording. **The tool**:
  `record_screen` takes `keys` (`off`, the default, or `shortcuts`; an enum so a later mode needs no
  rename), read with the caller's own mistakes after `include_framejob_windows`, an unknown value
  refused with the vocabulary; refused by name with `source` `voice_over` and `camera` (the
  screen-only lists); the grant read right after the Microphone grant and before `project`,
  refused with `inputMonitoringRefusal` (the pane sentence plus `launchClause`); never requested,
  and System Settings never opened (decision 4). **The recorder** (`ScreenRecorder.start`) refuses a
  `shortcuts` choice with the same sentence when the grant is absent (after the microphone's
  grant) or when the tap cannot be made (after the cursor capture is made); it never requests or
  opens anything. It amends CU-3 (the pane opens on the first press too).
- **CU-63 — CU6's proof.** `cursor_keys_probe.py` (no grant, no app): B0 the build; Y1
  `inputMonitoringStep` equals `screenStep` over all eight inputs, the pane URL ends
  `Privacy_ListenEvent`, the refusal starts with CU-3's sentence, the notes; Y2 the status item's
  titles with and without keys (the keyless title the old string), `menuTitles(paused:keys: true)`,
  `itemLength(keys:)` against every keyed title at W1's times and its formula; Y6 `CursorKeyFilter`
  over at least 40 synthetic events; Y7 `CursorSegments` fed shortcuts and typed marks into a body
  `ReelCursor(data:)` accepts, a key between `end` and `open` dropped, `.none` writing nothing;
  Y8 the panel under a spy (the box and its note under Show Clicks, persistence, `keys` and the
  greying, the press order, the launchd, second and shell presses, granted, box off); Y9 both
  status-item constructions pass `keys:` from `recordsKeys`. `cursor_keys_proof.py`: Y5 over MCP
  (`keys` without the grant refused with CU-3's sentence, a note by name when the grant is held;
  with `voice_over` and `camera` refused by name; `keys: "all"` the vocabulary sentence; the
  schema's enum), and the granted tier in-process — Y3 a posted ⌘⇧F19 and five letters give one
  `cmd+shift+f19` (code 80) and five typed marks, Y4 five letters under
  `EnableSecureEventInput()` give no mark in that span and two after it — skipped by name without
  Screen Recording, Input Monitoring, post access or an unlocked console; Z1 no `Frame Job: ` log
  line. Mutants: `secure-ignored`, `typed-with-identity`, `shift-modifier`, `option-rule-dropped`,
  `indicator-omitted`, `press-skips-input-monitoring` (`cursor_keys_probe.py --mutant`),
  `tool-asks-input-monitoring` (`recording_probe.py`'s 10f), and the core's ⌥ arm removed by hand
  (`cargo test --release --test cursor_file`). `FrameJobRecordingKeys` is the recorder's twelfth
  `FrameJobRecording…` key, pinned off by the harness and `screens.py`. Person checks JOB-23 (the
  grant from a Finder launch) and JOB-24 (a real session).

## CU7 — Auto Zoom (2026-11-02)

Recorded before the code. CU-70…CU-77 are CU7's: Clip ▸ Auto Zoom… and the tool `auto_zoom` plan
ordinary zoom actions from the selected clips' cursor files through one core planner, `plan_zooms`
in `rc_cursor_query` (one track per clip; no new `rc_*` export, op or format), applied as one undo
step "Auto Zoom". The owner's answer (2026-11-01): Replace's default is **off**. Nothing here sends
anything anywhere, so nothing is keyed (CJ-3). It amends CU-25 (`rc_cursor_query`'s one-track
rule now belongs to the six reads; `plan_zooms` reads one track per clip and the project).

- **CU-70 — The visits, and the defaults.** Zoom 2× (1.25–4), Arrive before the click (`lead`)
  0.6 s (0.2–2), Stay after the last activity (`stay`) 2.5 s (0.5–10), Follow on, typing on.
  - **Anchors** are down clicks (any button) and, with `typing`, typing stretches (CU-25's, marks
    under 1.0 s apart, at least 3), each read inside its clip's played source window `[in, in +
    content_length_in_source)` (a stretch by its first mark), mapped to container time through S
    — `time_for_source` on a ramp, `⌊(s − in)/speed⌋` otherwise — and kept when that time lies in
    `[from, to)` (both optional, container ticks). A click's activity is its instant; a
    stretch's runs from its first to its last mark. A position is the movie px of
    `CursorTrack::to_movie` less half the media size (P, from the uncropped centre); a region
    written is in Q, P less the evaluated crop's centre at the action's start (`edit_zoom.rs`).
  - **Visits.** Anchors in time order; an anchor at or before the visit's last activity + `stay`,
    with no scroll burst (`scroll_bursts`: wheel events under 1.0 s apart, at least 3) starting
    after that last activity and before it, joins the visit; else it starts a new one. `visits`
    counts these groups.
  - **A visit's actions.** A zoom-in `[a − lead, a)` ending at its first anchor; for each later
    anchor outside the region in force's inner 60 % (|Δ| > 0.3 of a side), a pan `[a − lead, a)`
    starting no earlier than the previous planned action's end, none when that leaves under one
    frame; with `follow`, the raw cursor sampled at 10 Hz from the zoom-in's end to the zoom
    back's start, and a pan of 0.5 s when it has been outside the inner 70 % for 0.3 s — at most
    one per 1 s start to start, starting after every earlier planned action ends, meeting no later
    anchor's `[a − lead, a)` and ending by the zoom back's start, aimed at the cursor then; a zoom
    back of 0.8 s starting at the last activity + `stay`, or at the first scroll burst starting
    after the last anchor when that is earlier. Each pan's region is centred on its aim.
  - **Merging.** When a visit's zoom back would end under 1 s before the next visit's zoom-in
    starts, both are replaced by one pan `[a − lead, a)` ending at the next visit's first anchor
    (starting no earlier than the previous planned action's end), and the two are planned as one
    hold (follow runs on through it).
  - **The region** is `region_size(canvas, rest_scale × zoom, rotation)` — the canvas's aspect, so
    `fit` solves to exactly that scale — centred on its aim and clamped inside the landing clip's
    cropped source rect; on an axis it exceeds, centred on that rect. `fit: "fit"`, `curve:
    "ease_in_out"`.
  - **Spans** are moved onto clips by CU-74, then snapped as `add_action` snaps them (clip-time
    `at` and `duration` each to the nearest frame), held inside the clip (an end past it pulled
    back), and dropped under one frame. A planned span meeting an earlier planned one on the same
    clip after the moves starts at its end (dropped when nothing is left).
- **CU-71 — Replace (owner: off by default).** With `replace`, every action of a given clip that
  `is_zoom` (CU-73) and meets `[from, to)` (the whole clip when absent) is removed first — never a
  layout, speed, colour or any other action; each later given clip of a run whose base is off the
  rest placement and that no kept action `moves` is reset to it (`set_video`) unless CU-74 sets
  it. Replace on or off, a planned action whose snapped span meets a KEPT action on its clip (any
  kind, a Speed action among them) is dropped and counted in `dropped`, so no op refuses at apply.
- **CU-72 — Typing's aim** (CU-S3 `dirty=not-stored`): the last down click at or before the
  stretch's first mark, anywhere in the file; else the raw cursor at that mark.
- **CU-73 — Actions are classed by content (`action_class.rs`, CJ-8 (i), CO-63).**
  `PLACEMENT_KEYS` = `x`, `y`, `scale`, `crop`, `corner_radius`, `opacity`. `is_zoom`: `end.video`
  an object whose keys are exactly `scale`, `x`, `y`; `end.audio` and `end.text` absent, null or
  `{}`; `end.graphic` absent, null or with `props` absent or `{}`; `end.speed` absent or not a
  number — the twin of `ActionBands.isZoom`. `is_layout`: `end.video` names all six. `moves`:
  `end.video` names any of the six.
- **CU-74 — Runs, the rest placement, and nothing straddles a cut.** A run is clips on one track,
  each touching the one before (`B.start` = `A.start + A.duration`), of one media, both forward,
  with `B.in` = the `in` of `source_advanced_through(A, A.duration)`; runs are formed over the
  whole track, so an unselected first half still sets the rest, and anchors come from given clips
  only. The **rest placement** is the run's first clip's base `scale`, `x`, `y`. **Every zoom
  back ends at it**: `region: null` when its clip's base as it will be at apply (after the plan's
  own `set_video` ops) equals it (each to 1e-9), else `region_for_placement` solved against that
  same post-`set_video` clip (`edit_zoom.rs`, the inverse of (★)). **Planned actions land only
  on given clips.** A span straddling a cut is moved, duration kept, to end at the cut when its
  midpoint is before it, else to start there — but never onto a clip that was not given: then it
  goes to the given clip's side whatever its midpoint — then held inside the clip. **A hold
  crossing a cut** into a given clip sets that clip's base to the placement in force there
  (`zoom_placement` on it, one `set_video`), unless that clip is not given or has a kept action
  meeting the hold: then the visit closes with a zoom back of 0.8 s ending at the cut (counted
  in `closed_at_cut`), and later anchors start a new visit.
- **CU-75 — The refusals, in order, each its own sentence.** An argument out of range ("zoom is
  Z; it runs 1.25–4", "lead is L s; it runs 0.2–2", "stay is S s; it runs 0.5–10"), or `to` not
  after `from`; no clips; a track count unlike the clip count; no project; then per clip in the
  given order: named twice, unknown, not a media clip, its media with no cursor file, reversed
  ("clip C plays reversed; Auto Zoom plans only clips that play forward" — CU-5), no picture,
  and **placed**: the run's rest scale below the scoped project's `Project::fit_scale(sw, sh)`
  (1 for a source that already fits, or with `fit_new_clips` off) by more than 0.1 % — "clip C is
  placed smaller than the canvas; a zoom would fill the canvas. Nest it (Clip ▸ Nest) and run
  Auto Zoom inside the nest." A screen scaled up and moved is planned; inside an open nest the
  scoped project's canvas is the nest's.
- **CU-76 — The doors.** Clip ▸ Auto Zoom… (after Add Action, no key), on with at least one
  selected clip, each a media clip whose media has a cursor file, and no sheet; allowed in a nest.
  The sheet: Zoom (×, 1.25–4), Arrive before the click (s), Stay after the last activity (s),
  Follow the cursor while zoomed, Zoom on typing (on and enabled only when a file has typing
  stretches; never remembered), Replace existing zooms (off). It opens with the remembered values
  (`FrameJobAutoZoomZoom`, `…Lead`, `…Stay`, `…Follow`, `…Replace`), reads the files off the
  main thread ("Reading cursor files…", Zoom disabled), re-plans at each change and shows "N zooms
  in V visits" and "D dropped where an action is already set", or the refusal or a missing file's
  sentence; Zoom applies the plan as one "Auto Zoom" and then writes only the keys whose value
  changed. `-RCDevAutoZoomAccept YES` (dev tools only) presses Zoom once the first plan exists.
  **The tool** `auto_zoom {clip | clips, zoom?, lead?, stay?, follow?, typing?, replace?, from?,
  to?, project?}` takes no `scope` key (dispatch reads `scope` only for op names; CJ2b's and
  CU5's precedent): it acts in the container `set_scope` has open, on the server thread — the
  call resolved on main, the files read off it, then on main refused if the project or scope
  changed, planned and applied; with no ops it answers `ok` with a `note` and makes no undo step.
- **CU-77 — CU7's proof.** `cu7_proof.py` Z0–Z4, Z6–Z11 over MCP and `cu7_probe.swift` Z5;
  `core/tests/auto_zoom.rs` the core halves; nine mutants (the merge gap ignored, the region not
  clamped, clip time without S, Replace removing non-zoom actions, the lead after the click, a
  later half's zoom back as `region: null`, a span straddling a cut, the placement check removed,
  the sheet's Arrive not passed); JOB-25 the person check.
