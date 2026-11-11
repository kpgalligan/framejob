# Spec §11 — decisions: Creator jobs, Make Vertical following the speaker onward (road map "creator-jobs", from 2026-11-04)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs-12.md`](creator-jobs-12.md), so a citation never has
to say which file. This file holds VR-64…VR-68 (VR6b), the fixes batches c1 and c2 (#456, #458,
#459, #460, #444, #438), #546 and TX-37…TX-39 (Find in the Transcript tab). It is the series' newest
file: each new decision is appended here, before its code; `creator-jobs.md` says what the road map
builds and how its IDs are made (CJ-7). It is new because `creator-jobs-12.md` had passed the spec's
~500-line split rule (#548, 2026-11-11); the entries moved here unchanged, and an "above" or "below"
in one may now point into a sibling file.

## VR6b — Make Vertical follows the speaker (2026-11-04)

Recorded before the code. VR6a gave agents `reframe_clip {follow: speaker}`; VR6b puts it in File ▸
Make Vertical Version… and `make_vertical_version`: a wide shot of two to four people beside their
microphones cuts to whoever is talking, the faces matched to the microphones automatically and
the sheet confirming (the owner's answer of 2026-11-01). One FFI export (`rc_project_speaker_match`,
a query); no op, op-table, tool count (124), `Kind` or format change (43 stands). Nothing is sent
anywhere, so nothing is keyed (CJ-3).

- **VR-64 — `make_vertical_version`'s `follow: speaker`.**
  (a) **Arguments.** `mics`, 2–4 clip ids, each standing for its TRACK as a microphone;
  `mic_faces`, optional, one face number per microphone in `mics`' order. Both are read only with
  `speaker` and ignored otherwise (VR-60 (a)'s rule).
  (b) **Speaker clips.** A class-3 media picture (VR-33) whose file is present and whose media has
  no cursor file, not on a microphone's track, whose span overlaps a clip with audio on at least
  two microphone tracks. Its own `mics`: per microphone in order, the media clip with audio on
  that track, one with its sound on before one with it off, then the greatest overlap with it
  (ties: the earlier start, then the lower id); a track with none is left out, with its
  `mic_faces` entry. A track whose only clip under the shot has its sound off still counts toward
  the two and stays in `mics`, so the core's sentence reaches the entry's reason.
  (c) **Step (3) with `speaker`.** Every `settings.follow.follows` test in the plan and the tool
  (`VerticalVersion+Plan.swift`'s missing and cursor branches, `AgentServer+VerticalVersion.swift`'s
  targets and `cursor`) becomes `VerticalVersion.analyses` (`follows || speaker`), so a missing
  picture is kept with its note and a picture whose media has a cursor file follows its cursor (or
  is shown whole) exactly as under the other analysing follows. A speaker clip gets `reframe_clip
  {follow: speaker, mics, mic_faces, zoom, where_empty, from_*, backdrop}` with its subjects; every
  remaining present, analysed (non-cursor) media picture gets `face`. A refused speaker framing is
  retried as `face`, its entry `followed` with the reason "it follows its faces, not who is
  talking, because " + the core's sentence, joined with `followedEntry`'s reasons by " and "; a
  refused `face` is retried as `keep` (VR-34), its entry `not_followed` with the face's sentence.
  (d) **Turns.** `withTurns` fills each speaker clip's `subjects.turns` through
  `FramingSpeaker.turns` with `silence: .notTalking` on the last main hop (the sheet's refresh,
  the tool's last hop): a microphone with no speech under the shot gets no turn, that person not
  talking there, and a shot with no turn at all is the core's to refuse and (c)'s to retry as
  `face`; a `FramingSpeaker.Refusal` (a microphone still being analysed, no speech detection, an
  unreadable plan) refuses the tool "make_vertical_version was refused: " + its sentence, nothing
  made (amended by #527).
  (e) **Refusals**, after VR-36's, in order: the `follow` sentence names speaker ("follow must be
  subject, face, person, salient, speaker or center, not X."); `follow: speaker` without `mics`:
  "make_vertical_version's follow speaker needs mics: two to four clips, one on each microphone's
  track."; an unknown id: `clipArg`'s error; no speaker clip: "make_vertical_version found no
  full-frame movie clip playing beside two of the microphones in mics, so nobody is framed by who
  is talking." The count, a repeat, a microphone that is not one and `mic_faces`' shape are the
  core's (VR-60 (d)) and reach the entry's reason; Swift restates none.
  (f) **The answer** gains `speaker [{clip, mics, mic_faces}]`, one per speaker-framed clip in id
  order, `mic_faces` the given ones or `clip_speaker_match`'s assignment; the summary adds
  " Follows whoever is talking in N clip(s)." after the cursor sentence.

- **VR-65 — The match crosses the FFI.** `rc_project_speaker_match(p, clip, args_json)`
  (`ffi_query.rs`, no `err_out`, no handle): `args_json` is `{"mics": [id, …], "subjects": {…}}`,
  `subjects` read by `reframe_clip`'s strict reader and `check_subjects`; the answer, compact, is
  `{"faces": [{"face", "x", "samples"}, …], "agreement": [[r, …], …]` (`[mic][face]`),
  `"assignment": [face per mic], "sure": bool}`, and with fewer faces than microphones the empty
  answer (`faces`, `agreement`, `assignment` [] and `sure` false); NULL for a NULL project or
  args, an unknown clip, a clip that is not a media clip, malformed or failing args, or `mics`
  empty or over 4. `reframe_speaker_match.rs` gains `clip_turns` (`plan_speaker_framing`'s turn
  clamp, a pure move: timeline → clip ticks, clamped to `[0, duration]`, empty dropped) and
  `clip_speaker_match` (`in_clip_time`'s samples, `clip_turns`, `faces_of`, `matched`), so the
  sheet shows the core's own assignment and face places; Swift computes none.
  `ReelCore+Framing.swift`'s `ReelProject.speakerMatch` is its one caller.

- **VR-66 — The sheet.**
  (a) **Follow**: Subject, Faces, People, Salient Region, Speaker, Center
  (`VerticalVersion.follows`). Speaker is remembered in VR-29 (c)'s key; Follow Subject's sheet
  reads a stored `speaker` as Subject (its rule for a value outside its list) and gains no Speaker.
  The sheet's `opened`, fresh and restoring alike, is `VerticalVersion.remembered(.standard)`
  (`FollowSubjectSettings` with `follow` the key's value when in `follows`, else `subject`; Where
  Empty as `FollowSubjectSettings.remembered`; zoom 1), so `remember(changedFrom:)` compares
  against what Follow showed and Subject chosen after a stored `speaker` is written.
  (b) **With Speaker**: "Microphones:" one checkbox per `VerticalVersion.microphones` track (a
  track holding a clip `SpeakerSwitch.playsSound` takes whose media has no video, front to back,
  titled by the track's name, its `clip` the earliest such clip), the first four ticked; "Faces:"
  one row per ticked microphone, the track's name and a pop-up of "Choose a face" and "Face N
  (X % across)" per face found; then a muted note.
  (c) **The reading.** The reference clip is the longest speaker clip (ties: the lower id).
  `speakerReading` (main) fills the turns (`withTurns`) and asks the match on the reference clip
  with its own microphones; only a `.ready` reading is cached, per ticked set, and a `.refused`
  one is read again at each `refresh()`, so a loudness cache landing while the sheet is open
  clears it. `.refused` shows its sentence (SW-24's still-being-analysed sentence (#527), or
  with no speaker clip "No full-frame movie
  clip plays beside two of the ticked microphones, so nobody can be framed by who is talking."),
  Make off.
  (d) **The confirmation.** A `sure` match presets the pop-ups to its assignment, the note "Each
  microphone is matched to the face that talks with it; change one if it is wrong."; not sure, or
  no match, leaves them on "Choose a face", the note "The faces do not show clearly who is on each
  microphone: choose each microphone's face." The preset is made once per ticked set. Make is off
  until 2–4 microphones are ticked, a speaker clip exists and every ticked microphone has a face,
  each its own. Make passes `mics`, `micFaces` (always the confirmed faces) and the subjects with
  their turns.
  (e) **Analysis missing.** The pending summary reads "Finds the faces, people and shot changes in
  N files on this Mac first, then asks you to confirm who is on each microphone, then makes a W × H
  version."; after the Analyzing sheet lands, the editor presents the sheet again from the
  hand-off (`restoring`): its shape, follow, zoom, where empty, copy and ticked microphones.
  Nothing is made until Make there. `-RCDevVerticalAccept` presses each sheet's Make once it is
  first enabled.

- **VR-67 — The documents.** `docs/guide/vertical-and-framing.md`'s Make Vertical section gains
  Follow Speaker for people and the `speaker` bullet loses "There is no menu for it yet."; the
  README's Vertical and framing highlight names whoever is talking; `menus-and-shortcuts.md`'s Make
  Vertical row lists Speaker; `15j-make-vertical-sheet`'s prose lists Speaker and the Microphones
  and Faces rows (no new screen: the catalog pins Follow to Subject, and the proof's Q6 dump stands
  for the Speaker block); JOB-37 between JOB-36 and JOB-39; spec §7.1, §7.4, §7.9i and §7.10.

- **VR-68 — VR6b's proof.** `core/tests/speaker_match_ffi.rs` (the two-face answer equals
  `speaker_match` on the in-clip samples; a clip at a timeline offset and a ×2 clip map turns as
  `plan_speaker_framing` does, not sure exactly when it refuses the weak match; fewer faces → the
  empty answer; NULL for a NULL project, an unknown clip, a text clip, malformed args, `mics` []
  and five mics). `tools/proof/vr6b_proof.py` over F-TURNS (`f_turns.py`, exit 2 skips by name) on
  a 1920 × 1080 30 fps canvas — `cam_wide.mov` W with VR6a's two canned faces and landmarks, Mic A
  and Mic B at 0, a second movie S after the microphones' span with one canned face — rows Z0 and
  Q1–Q8 (launch 1 `-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`: Q1 the tool with `mics`,
  W equal to a reference document's `set_canvas`, `add_track` and `reframe_clip {speaker}`; Q2
  `mic_faces: [2, 1]`; Q3 constant mouths retried as `face`; Q4 the four refusals; launch 2
  `-RCDevAnalysisCanned YES -FrameJobFollowKind speaker -RCDevVerticalAccept in-place`: Q5 the menu
  in place, W equal to Q1's; Q6 the not-sure sheet's dump; Q7 an uncanned analysis, the sheet
  presented again with both microphones ticked; Q8 `vr6b_probe.swift`, the remembered key read
  back), expected values from a reference `reframe_clip` or the manifest, never the code under
  test, under a scratch `CFFIXED_USER_HOME`. Eight mutants, each once on the final instrument:
  every present picture a speaker clip (Q1); a refused speaker retried as `keep` (Q3); `micFaces`
  not passed (Q2); the picker presetting when not sure (Q6); the picker's preset transposed (Q5); a
  Speaker hand-off committed after the analysis instead of presented again (Q7); `withTurns`
  filling nothing (Q1); `remembered` ignoring `.speaker` (Q8).

### Amendments recorded by VR6b

- **VR-29 (c)**: the Follow key may hold `speaker`, written only by Make Vertical's sheet; Follow
  Subject's sheet reads it as `subject`.
- **VR-34** (3): the speaker branch, the speaker → face → keep chain and `Plan.speaker` (VR-64 (c),
  (f)); `where_empty` is sent to `speaker` as to the following kinds.
- **VR-35**: VR-64 (f)'s sentence.
- **VR-36**: `follow` gains `speaker`; the arguments `mics` and `mic_faces`; VR-64 (e)'s refusals;
  the answer's `speaker`.
- **VR-39**: Follow gains Speaker with its Microphones and Faces rows (VR-66); `opened` is
  `VerticalVersion.remembered`; a Speaker hand-off that analysed presents the sheet again.

## Fixes batch c1 (2026-11-09)

- **#456 — An empty range gets no no-face refusal, and a marker range past the grid is
  skipped.** With `from == to` the range has no step, so every read face angle's `activity` has
  `count == 0` values and none of them is a value: SW-84's loop added "shows no face whose mouth
  can be read" beside the microphones' own no-speech refusal, which is the range's real reason.
  The loop now runs only when `count > 0`; `silentMicrophones` is unchanged, so an empty range's
  refusal is the no-speech sentence alone, and no new empty-range refusal is added. A `faces`
  marker range clamped to the grid (`max(0, lower)...min(grid.lastIndex, upper)`) crosses when
  the range begins past the grid's last index — a marker written over a longer media, or a grid
  read at another rate — and forming that `ClosedRange` traps. `SpeakerSwitch.storedActivity`
  and `AnalysisMasks.run` skip a range whose clamped bounds cross: it covers no index of this
  grid, so nothing is read and nothing is published for it. Amends SW-84.
- **#458 — The landing's follow-ups read the landing's own container.** The voice clips, their
  presence and readiness (AU-68 (a), (b), (d)), the screen clips, their cursor files and media
  (CU-101 (b), (c), (j)) are read in `RecordingEnhance.container(of:scope:)`, the landing's
  container (the nest it landed in, or the top level), never `editedProject`. Before, a nest
  opened while a follow-up waited made the open container the nest: the landed clips were not in
  it, `decide`'s first arm answered `.drop`, and the follow-up was lost ("No screen clip with a
  cursor file landed…") although the scope test was there to wait. Now the clips are still found,
  the moved scope is busy (AU-68 (c), CU-101 (d)), `decide` answers `.wait`, and the follow-up
  runs once the person returns, or gives up at 300 s as before. At the tool door,
  `landAndEnhance` reads `document.scope` and, when the choice asks for Enhance, the voice clips
  in the main hop that runs `land`, and hands both on; no later hop reads them, so a nest opened
  between hops cannot empty them. The panel door already reads both in the landing's own hop
  (`follow`). `isReady` (which reads the open container) is evaluated only when not busy, at both
  doors; busy reads not ready. `decide`'s arms and order, the sentences, the clocks and the 300 s
  limit are unchanged. Amends AU-68 (a), (d) and CU-101 (b), (d), (j).
- **#459 — A cache file that vanishes during the carry is skipped.** The thumbnail pass's
  `clearThumbnails` (`MediaCacheFiles`) is the one remover of the source's cache not held off by
  the ledger's save bracket, so a `thumbs/<id>/` tile listed for the carry could be gone when it
  was cloned, and New Project from Range or Make Vertical then failed ("cache/thumbs/3/40.jpg
  could not be carried: No such file or directory"). The carry is now two steps,
  `DerivedCarry.listing` (each listed path that exists: a file as itself, a folder as itself and
  its regular files; a folder that vanishes while it is enumerated contributes nothing) then
  `copy(_ listing:from:to:)` (every folder created, then every file cloned). A file whose clone
  fails while the source no longer exists is skipped and not counted in the report; the
  derived document's own thumbnail pass makes its tiles again. Every other failure still throws
  "cache/<path> could not be carried: <reason>". Skipping was chosen over bringing the tiles into
  the bracket: a vanished tile is a cache the copy rebuilds, and the bracket would hold the
  thumbnail pass for the whole carry. Amends CJ-51 (c).
- **#460 — A vertical copy whose save fails is closed and its package removed.** With `path`,
  `make_vertical_version` saves the copy on the server thread after `verticalCopy` opened it at
  `path`. When that save threw, the copy stayed open and dirty, its package held the project
  before the step, and the error had no `project` to name it. Now any throw from the save closes
  the copy (on main), removes the package at `path`, and answers the save's error unchanged —
  `ProjectDocument.verticalCopy`'s own shape for a copy the step did not change. A dev-tools build
  reads `-RCDevVerticalSaveFault <name>`: a save to a `path` whose last component is `<name>`
  throws before it is attempted, so a proof can see the cleanup; Distribution never reads it.
  Amends VR-36.

## Fixes batch c2 (2026-11-09)

- **#444 — A voice cache replaced under shown cloud words is read again at once.** TX-34 said a
  voice cache REPLACED under a shown cloud-transcribed media kept the old one in the tab's table
  until the tab showed again (filed). That clause is replaced. A `speech` landing now calls
  `TranscriptTabSource.reloadSpeech(media:)` after TX-18's `reloadDeviceWords` (which moves the
  media's epoch) and before `update()`. It always drops the media's kept voice cache and the
  table, so the next `cutTable()` reads the landed file, as it already did for a media with none
  kept: the word cuts (TX-30) and the pause tokens follow the new cache. When the tab is shown,
  the media's words are there and no TX-18 re-read covers it (its words are not this Mac's), its
  pause set and voice cache are read again on the load queue at the media's epoch. They are
  merged and rebuilt only while the tab still shows words of the same engine; when a landing came
  during the read (the epoch moved), the media is read again instead. So the paragraph breaks
  (TX-22) follow the new cache too. A cloud load that read the media before a landing and merges
  after it (its epoch moved) merges its words and then calls `reloadSpeech(media:)`, so it never
  keeps the voice cache or pause set it read before the landing. An `.apple` media is unchanged:
  TX-18's re-read reads its words, pause set and voice cache. A peaks landing also moves the
  epoch; a cloud load that crosses one is read once more, which is harmless. Amends TX-34.
- **#438 — Remove Background's status: the shut header follows, no nil stamp is memoised, and
  `analyze_cutout` re-reads only what is still analysing.**
  - (1) A tick of `CutoutStatus.Memo` that does not change the state's kind (a recompute of the
    same kind, or a progress-only tick) refreshes the read-out's enclosing `InspectorSection` —
    its rows and its header summary — not the read-out alone. The Background section is shut by
    default and its summary repeats the Status words for one clip, so before it kept showing the
    first "Analyzing N %". The section's `summary` reads the memo's held status, so this refresh
    reads nothing again and starts no second ticker. Amends CO-30 (d).
  - (2) `CutoutStatus.stamp` memoises only a non-nil stamp; a nil one is answered and its key's
    entry removed, so it is read again on the next call. Before, a transient "Failed: the media
    file cannot be read" (the file briefly absent) stayed for that media, URL and LUT for the
    rest of the process, Analyze Now included. `analyzeMasksNow()` is unchanged. Amends
    CO-31 (a).
  - (3) `analyze_cutout`'s poll keeps the details it read with the document's `project` and
    `editedProject` handles (`AgentServer.cutoutDetails`, `CutoutPoll`). While both handles are
    the same (`===`), a clip whose kept detail is settled (anything but analysing) keeps it and
    only the others are read again; any change of either handle, an edit during `wait`, reads
    every clip again, as the pane's memo does. The quality and the project summary are still read
    in each hop. The answer's shape and the refusals are unchanged. Amends CO-31 (b).

## Fix #546 (2026-11-09)

- **#546 — The polish waits for Enhance's measurement, not only its timer.** AU-68 (e) ends
  Enhance's follow before anything is shown, so `RecordingEnhance.isPending` was false for the
  whole measurement, and the polish's follow (CU-101 (a), (f)) was then held only by the
  Measuring Sound sheet being attached. The sheet hands its answer back a main-queue turn after
  it has gone; in that gap the polish's 0.5 s timer could fire and commit Auto Zoom (measured on
  Debug: 21 ms before the hand-back), and `AudioMeasureDoor.measure`'s stale test then refused
  Enhance ("…Choose Enhance Voice again."), so its step was lost. No build was exempt: the timer
  either landed in the gap or did not.
  - (a) **The measuring state.** `RecordingEnhance.tick`'s `.enhance` step makes a
    `RecordingEnhance.Measurement`, counted per document, and `AudioMeasureDoor.enhanceLanded`
    takes a `done` it calls exactly once, after whatever the call ends in has landed: each
    refusal before the run, the no-render answer, the sheet's hand-back (the commit, a refusal or
    the stale refusal; the document gone), the sheet's Cancel and a run with no outcome.
    `AudioMeasureSheetController` gains `stopped`, called in `finished`'s place on the same turn
    after `viewDidDisappear`, so one of the two always runs for a sheet that was shown. A
    `Measurement` released without `end()` uncounts itself, so a hand-back dropped uncalled
    cannot hold the polish. `isMeasuring(document)` reads the count; `isUnderWay` is `isPending`
    or `isMeasuring`. `isPending` keeps AU-68 (e)'s meaning, the timer, and never depends on the
    sheet.
  - (b) **Who reads it.** The polish's panel follow (`enhancing`, and so CU-101 (a)'s clock
    restart) and the tool door's `polishLanded` read `isUnderWay`. The tool door's own Enhance was
    never exposed — `enhanceVoice` returns before `polishLanded` starts — but its `decide` read
    `isPending` for a panel landing's Enhance in the same document, and its busy test has no sheet
    arm, so it had the same gap, wider; it now waits for that measurement too.
  - (c) **`land_recording`.** `follow_wait` waits while `isUnderWay` or the polish is pending, and
    `enhance_pending` answers `isUnderWay`. Before, `follow_wait` returned when the timer ended,
    about 2.7 s before the step, and an `undo` read then was itself the edit that made the
    measurement stale.
  - (d) **The dev hold.** `-RCDevMeasureHandBackHold <s>` (dev tools only) holds the Measuring
    Sound sheet's hand-back, `finished` or `stopped`, s seconds after `viewDidDisappear`, so a
    proof makes the gap wider than the polish's check interval instead of relying on where a
    timer lands.
  - (e) **The proof.** `cu10_proof.py` P5 requires "Auto Zoom", "Enhance Voice", "Add Recording"
    exactly, on every build. P6 and P7 run on an instance held 2 s: Enhance alone with
    `follow_wait` (undo read straight after the answer: "Enhance Voice", "Add Recording";
    `enhance_pending` false), and Enhance with Auto Zoom (all three names, both pendings false).
    Mutants: `polish-ignores-measuring` (P7) and `wait-ignores-measuring` (P6).
    `audio_ap6c_probe.swift`'s P5 also reads `isMeasuring` false after a no-render refusal.
  Amends AU-68 (e), AU-69 (e) and CU-101 (a), (j).

## Find in the Transcript tab (#434, 2026-11-10)

Recorded before the code. The owner asked for it on 2026-11-01 as "⌘F later, unless it comes
free" (TX-20), and on 2026-11-10 to begin it. No owner question was asked.

- **TX-37 — Edit ▸ Find… (⌘F) finds in the Transcript tab, in Frame Job's own bar.** The item is
  the Edit menu's last, after a separator, enabled while the window's Transcript tab shows and no
  sheet is attached, whatever has the keys. ⌘F was free; ⌘G and ⇧⌘G are Nest and Un-nest, so the
  usual Find Next keys are not offered. **Not `NSTextFinder`**, which #434 named, for four
  reasons: its bar is a system search field in the editor window, whose Return K-4 (3) spends
  before the field sees it; it shows the current match by setting its client's selection, and a
  selection here is the in/out range (TX-31), so every Return and every keystroke of an
  incremental search would move the range; its only search string from code is the shared find
  pasteboard, so a proof would write a system-wide pasteboard; and the panel's fields are
  `DSField` chrome (the Media search's own reasoning). What that gives up: the find pasteboard
  (⌘E) and the system bar's options. **No MCP mirror:** Find edits nothing and is view state,
  never saved, as the Media tab's search is; an agent reads `get_timeline_transcript`.
  - (a) **What is searched.** The words, not the view's string: each paragraph's token texts
    joined by one space, paragraphs separated by a line break, and a line break rather than a
    space before a token with `collapsedBefore > 0`. So a timecode, "⋯" and a pause label are
    never matched, a phrase is found across a pause label, and no match spans a paragraph break
    or a collapse.
  - (b) **How.** The query as typed, not trimmed (as `MediaListFilter.search`), compared ignoring
    case, diacritics and width (what `localizedStandardContains`, the Media search's test,
    ignores), left to right, never overlapping. A match is its token range and, per token, the
    part of that token's text it covers. A match covering no token character (a query of spaces)
    is dropped; an empty query, or one holding a line break, has no matches.
  - (c) **The current match.** An anchor token is set as the bar opens: the selection's first
    token, else the highlighted word, else the top visible token, else 0. While typing, the
    current match is the first one starting at or after the anchor, else the first. Return or
    Next (›) moves to the next match and ⇧Return or Previous (‹) to the one before, wrapping,
    and the anchor moves there. With no match they beep. The count reads "3 of 12", "No matches",
    or nothing for an empty field.
  - (d) **What Find moves.** Only the scroll position and its own marks. Every match is marked
    behind its text in `NSColor.findHighlightColor` at 0.3, the current one at 0.65 with a 1.5 pt
    outline of the same colour (a strength that keeps the words readable in both looks), under
    the selection and the highlight; a phrase is one mark, and a pause label between two of its
    words is not marked. The current match is scrolled into sight by `setHighlight`'s rule (a
    third from the top when it is outside the margins), **after the text from the top through
    the match is laid out**, the match's own paragraph invalidated first. One scroll onto a
    measured rect is not enough: a far word's rect and the view's own height are estimates
    until the text above is laid out (measured on 27,000 words in 900 paragraphs: the last word
    estimated at 88,601 pt and laid out at 130,078 pt, in a view 979 pt tall, so the scroll was
    clamped short; a paragraph measured early keeps its estimated place). Laying out all 27,000
    words took 0.06 s, once; drawing still lays out only what shows. The selection, the range, the playhead and the undo stack are
    untouched, bar open or closed. To act on a match the person clicks its word, which works
    with the bar open and leaves it open. Only the matches whose tokens meet the dirty rect are
    measured, so TX-21's viewport layout stands with a match in every word.
    **Amended 2026-11-11 (#558):** the layout step is `TranscriptView+Layout`'s
    `layOut(through:)`, and the click-to-clip scroll (TX-20, `scrollToToken`) and the follow's
    scroll (TX-22, `setHighlight`, only on a tick that scrolls) take it too. Measured before, on
    the same 27,000 words: `scrollToToken`'s two scrolls left word 18,000 some 1,850 pt below
    the visible rect, and six ticks of the follow never showed it. The step also lays out a
    viewport's height below its target and invalidates those paragraphs first: the view is only
    as tall as what is laid out from the top, so laid out through the word and no further the
    word came to rest at the visible bottom, and a paragraph laid out on its own keeps its
    estimated place (the one after a paragraph at 86,015 pt placed at 58,837 pt). The follow's
    step costs 1.4 ms once the text above is laid out. The scroller's knob is left as it is: it
    reads the scroll against the height laid out so far (0.995 at word 18,000 of 27,000), since
    the text below the viewport is not laid out (TX-21). A rebuild's anchor restore is not
    changed either: it keeps the top word (measured: the same top word, 9 pt lower), and the
    step there would lay out everything above the anchor on every rebuild.
  - (e) **Keys and focus.** ⌘F opens the bar and gives its field the keys, its text selected;
    with the bar open it only does that again. In the field Return is (c)'s next and ⇧Return its
    previous, and the field keeps the keys: K-4 (3)'s one exception, decided in the window with
    the event in hand (`TextFocus.keptReturn`, asked before `leavesOnKey`; the field is a
    `TextFocusKeepsReturn`), so ⇧ is read from the key itself. The bar is the field's host for
    K-4 (1) (`TextFocusHosting`): a press on Previous, Next or the count leaves the keys in the
    field. Tab and a click outside the bar still hand the keys back by K-4, and the bar stays
    open. Esc in the field, Done, or Esc in the transcript's text with nothing selected (a
    selection is cleared first, TX-21) closes the bar. Closing while the field holds the keys
    hands them to the transcript's text when it had them as the bar opened, else to the window's
    content view (K-4's target); keys anything else holds stay where they are.
  - (f) **The follow waits** while the bar is open (TX-22): playback does not scroll a match away.
  - (g) **A rebuild** (an edit, words landing, Words from, Language) recomputes the matches over
    the new words. The current match stays on its first word by identity, else the first match
    at or after that word's start; nothing scrolls.
  - (h) **Hiding the tab** (another tab, Hide Inspector, the window closing) closes the bar; keys
    its field holds go to the content view, never to a view not shown. The typed text is kept
    for the window and searched again when the bar next opens. **Found here and fixed with it:**
    AppKit leaves the WINDOW first responder when the view that was is removed, and there a bare
    key beeps, so after leaving the tab with the transcript's text focused J, K and L were dead
    (measured before the fix: first responder `EditorWindow`, L did not play). Out of sight, the
    pane now hands the keys to the content view whenever the window itself or the transcript's
    text holds them (`handBackKeys`), bar or no bar.
  Amends TX-20 ("⌘F later" is built), TX-21 (Esc), TX-22 (the follow) and K-4 (1), (3).
- **TX-38 — `transcript_view` drives Find.** `find: string | null` — a string opens the bar as
  Edit ▸ Find… does and sets the field's text through the field's own change path; null closes
  it by Esc's path. `find_step: "next" | "previous"` presses Return's or ⇧Return's path once,
  after `find`; refused while the bar would be closed (no `find` and the bar closed, or
  `find: null`). Applied after `click` or `select_pause`. The answer gains `find`: null while
  the bar is closed, else `{query, count, current, matches: [{first, last}] (the first 200),
  label, field_first_responder, current_visible}`. Amends TX-23.
- **TX-39 — The proof.** `tools/proof/transcript_find_proof.py` with
  `transcript_find_probe.swift`. Probe rows F0–F13 over the app's own editor window, keys and
  clicks through `NSWindow.sendEvent` (a press is then handed to the view it hit, because a
  window that is not key dispatches none; F12 holds that to one delivery): the search alone (F1), the validator and the open (F2),
  typing and the anchor (F3), Return, ⇧Return and keypad Enter (F4), Esc and the keys after it
  (F5), a click on a word and the two Escs (F6), a rebuild (F7), the follow (F8), hiding the tab
  (F9), a bare view of 27,000 words with a match in every one — the fragments its draw lays out,
  and the last match in sight once revealed (F10) — the marks' pixels (F11), a press on Next
  with the field typing (F12), and leaving the tab with the text focused (F13). App rows Z0 and A1–A5 over MCP: the argument set, the menu item's validation,
  the matches against the same rule computed in Python, phrases and paragraph breaks, a ripple
  under an open bar, and screen 11d (the `fillers` fixture, "er" found three times;
  `transcript_view` joins `screens.py`'s step tools for it, since Edit ▸ Find… is a `none` menu
  item that is no view toggle). **Fourteen mutants**, one per decision, over the root rule's ten
  because the plan's review named two decisions as unguarded and the build added two (the
  reveal's layout and the keys handed back):
  `return-leaves` (F4), `across-paragraphs` (F1), `case-sensitive` (F1), `anchor-ignored` (F3),
  `find-selects` (F4), `close-keeps-keys` (F5), `follow-while-finding` (F8),
  `stale-after-rebuild` (F7), `find-measures-all` (F10), `always-enabled` (F2),
  `hide-keeps-bar` (F9), `view-esc-passes` (F6), `reveal-on-estimate` (F10) and
  `keys-left-behind` (F13). Each is a probe mutant; the app rows are the same decisions read
  through MCP and name none. How the bar and the marks look, and a real ⌘F, are
  `docs/manual-checks.md`'s JOB-67.
  **Amended 2026-11-11 (#558):** probe row **F14** — `scrollToToken` on a fresh bare view of
  F10's 27,000 words, each target measured first where an estimate puts it: word 18,000 at the
  visible top and the top visible token; the last word in sight with the view's bottom at the
  visible bottom, at the height every paragraph laid out gives; a paragraph's first word less
  than a viewport from the end at the top or as the last word; and the follow to word 18,000 a
  third from the top, the next word's tick scrolling nothing. **Nineteen mutants**: #558 moved
  the reveal's layout into a step three callers share and gave that step two decisions of its
  own, each of which is one mutant, and two road-map items now share the instrument.
  `reveal-on-estimate` moves to the shared step (F10, F14); new are `reveal-skips-layout`
  (F10), `scroll-on-estimate` (F14), `follow-on-estimate` (F14), `no-viewport-below` (F14) and
  `below-keeps-estimate` (F14).
