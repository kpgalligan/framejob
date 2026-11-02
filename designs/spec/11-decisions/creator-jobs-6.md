# Spec §11 — decisions: Creator jobs, the pause token onward (road map "creator-jobs", from 2026-11-02)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The IDs continue the series of [`creator-jobs.md`](creator-jobs.md),
[`creator-jobs-2.md`](creator-jobs-2.md), [`creator-jobs-3.md`](creator-jobs-3.md),
[`creator-jobs-4.md`](creator-jobs-4.md) and [`creator-jobs-5.md`](creator-jobs-5.md) (CJ-, VR-,
TX-, SW-, CU- and CO-), so a citation never has to say which file; `creator-jobs.md` says what the
road map builds and how its IDs are made (CJ-7). This file is new because `creator-jobs-5.md`
would pass the road map's ~500-line split rule with TX3b's entry (468 lines, 2026-11-02); each
phase's decisions are appended here from now on, before its code.

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
