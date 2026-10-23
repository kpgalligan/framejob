# Spec §11 — decisions: Cut by transcript (road map "cut-by-transcript")

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

The road map that makes these is open: `designs/cut-by-transcript.md`, which holds each phase's
record (CT-0 the road map, these decisions and the filler spike; CT-1 fillers on the cloud
request; CT-2 `detect_fillers` and the cut; CT-3 Clip ▸ Remove Filler Words…; CT-4
`get_transcript` and false starts; CT-5 the close). TR-1…TR-6 were recorded in CT-0, before any
product code, from the owner's decisions of 2026-09-30 on issue #92 (its comment of that day,
quoted verbatim in the road map's "The owner's choices"), which the owner took up on 2026-10-22
("#92 Cut by transcript"). TR-7, the on-device filler source, was recorded on 2026-10-22 after
the filler spike ran on the owner's own scripted sample, before CT-2.
CT-1…CT-4 each record their numbers as a new entry (TR-8 on) or as Amended-by lines before their
code; TR-8 was recorded in CT-1, before its code.

**Stands, and nothing here re-litigates it:** R6-3 (one upload per media, every clip derived from
it, the words cached verbatim); R6-10 (`MediaTranscript.words(for:in:)` maps a media's words onto
a clip); AI-7 (the cloud `transcribe` stays withheld from the assistant); W-8 (the on-device
engine's asset download is a person's act, never a tool's); the silence road map's 32 ms grid
(Silero VAD's own grid, inward; `silence.md`). R6-15 and AI-6 are amended here, by TR-1 and TR-5;
W-9 is amended by TR-5 through AI-6.

- **TR-1 — Fillers come from AssemblyAI's `disfluencies: true`, sent on every cloud request from
  CT-1 on, and the transcript marker records it.** The owner's decision 1 (#92, 2026-09-30).
  - **The request:** `TranscriptOptions` and `TranscriptRequest` (`AssemblyAITranscript.swift`)
    gain `disfluencies`, true on every request CT-1 and later sends; `TranscriptStamp` records it,
    so a marker identifies the request it was made with, as R6-15 says a marker must. This
    amends R6-15.
  - **Captions look unchanged:** the caption producers (`CaptionPages.normalize`/`cues`,
    `CaptionLayout.place`) never see a filler: `MediaTranscript.words(for:in:)`'s caption callers
    drop them, against one filler vocabulary, so a caption made from a disfluent transcript is
    byte-identical to one made from the same words without the option.
  - **Why:** AssemblyAI reports "um" and "uh" only when asked, and a transcript-level cut needs
    them timed. Road map 6 refused the option because "um" is not a caption
    (`archive/roadmap-6.md` l.152); that refusal is superseded here, and the filter keeps the
    reason it was made.
  - Risk accepted: every cloud transcript from CT-1 on carries words no caption shows, and the
    vocabulary that drops them must match AssemblyAI's spelling, which CT-1 pins against its
    documentation and `assemblyai_fake.py`.
- **TR-2 — A transcript cached before CT-1 stays current for captions; it is re-transcribed only
  when the person asks for filler removal on that media, after the estimate line has shown the
  cost.** The owner's decision 1, its first sub-point.
  - **The marker rule:** a caption run takes a current marker whatever its `disfluencies` value
    (an old marker, with no key, reads as false); a filler run needs a marker with
    `disfluencies` true. Nothing re-transcribes on its own.
  - **The ask:** the Remove Filler Words sheet (CT-3) shows media with no disfluent transcript
    with its `CloudEstimate` line and a Transcribe button; the re-transcribe is that person's
    press, one media at a time as the sheet lists them.
  - Risk accepted: a project transcribed before CT-1 needs a second paid transcription before its
    fillers can be cut.
- **TR-3 — Two paths, split by who judges: fillers are deterministic, and false starts are a
  judgement of meaning.** The owner's decision 2.
  - A filler is a word in a closed vocabulary, found by its spelling and cut on its own timing:
    no judgement of meaning, so a pipeline may do it (TR-4).
  - A false start ("I was — we were going") is found only by reading what was meant, so no
    pipeline does it (W-9, AI-6); the assistant may, when the person asks (TR-5).
  - Risk accepted: a filler the vocabulary does not spell, or one the engine did not report, is
    not offered; a false start is never offered without a conversation.
- **TR-4 — Remove Filler Words… is shaped like Remove Silences: a sheet, a candidate wash on the
  timeline, one `ripple_delete_ranges` undo step, and its own read-half MCP tool,
  `detect_fillers`.** The owner's decision 2, its first sub-point.
  - **The pieces:** `detect_fillers` answers the ranges and cuts nothing, as `detect_silence`
    does (`AgentServer+Silence.swift`); the cut is the existing `ripple_delete_ranges`
    (`core/src/edit.rs`), so the menu command and an agent make the same single undo step. The
    sheet (`FillerSheetController.swift`, CT-3) is shaped like `SilenceSheetController`, and its
    wash comes from `TimelineView+Candidates.swift`.
  - **No new op and no format change:** a filler range is a range like a silence's; nothing new
    is persisted in the project.
  - **The edges:** on the Silero VAD's 32 ms grid (`MediaSpeech`, `SileroVAD.chunkSamples`),
    frame-snapped as `SilenceDetector` snaps; the exact rule is a TR entry CT-2 records before
    its code. That is #92's done-when: a known filler cut out of a fixture, its ranges read back
    through `get_project`, its edges on the grid.
  - Risk accepted: the cut is only as tight as the transcript's word timings and the grid allow.
- **TR-5 — False starts go to the assistant under AI-6, which this amends: the assistant may
  choose words to cut when the person asks, reading them through a new app-state tool,
  `get_transcript`.** The owner's decision 2, its second sub-point.
  - **The tool:** `get_transcript` answers a clip's words in timeline times, fillers flagged. It
    reads the current cloud cache when there is one, else runs the on-device engine over the
    clip's window, and it never makes a network call, so AI-7 still withholds the cloud
    `transcribe` and nothing about it changes.
  - **The rule:** no PIPELINE picks words by meaning (W-9, AI-6, unchanged). The assistant chooses
    words to cut only because the person asked in the conversation; it proposes, then makes
    ordinary undoable cuts (`ripple_delete_ranges`), each an undo step like any other edit.
  - Risk accepted: the assistant's choice of a false start can be wrong; the person sees the
    proposal first and undo takes back what it cut.
- **TR-6 — The working arrangement: the `transcript-cut` worktree, each phase gated, committed and
  merged into main alone.** The owner's ask of 2026-10-22.
  - The worktree is `~/devel/framejob-tcut` on branch `transcript-cut`, from `15d3545`; each
    phase passes `make gate`, is committed and is merged into main alone, with main's next
    numbers if main moved.
  - Fixtures are synthetic (`say`) and AssemblyAI is `assemblyai_fake.py`; a paid call runs only
    behind its explicit flags and the month's budget (P-3, P-6), and only when a change is likely
    to break what it tests. The owner's `tools/proof/media/owner-sync*` and `filler-sample/` are
    read in place and never committed or copied out.
  - Agents edit no `CLAUDE.md`; each phase's handback lists the edits owed.
  - Risk accepted: until the owner's scripted sample (o2) is recorded, no owner recording holds
    a known filler; a real recording's filler CUT stays a person's check.
- **TR-7 — Filler removal is cloud-only: the on-device engine is not a filler source.** Recorded
  2026-10-22, before CT-2, by the owner ("Cloud-only (Recommended)") after the filler spike's run
  on the owner's scripted sample (`tools/proof/filler_spike/`, `answers.json`).
  - **Measured** (macOS 26.5.1, en-US, on-device): on the owner reading the eight-filler script
    (o2, 29.4 s), the engine recognised 98.3 % of the script's other words and kept **1 of 8**
    fillers (the first "um"; the other two um, all three uh and both er dropped). On `say`
    speech it kept 6 of 8 (f1) and 7 of 8 (f2); the no-filler control kept 0. The spike's
    mechanical verdict is `reports-real` (any kept filler counts); one in eight is not a source.
  - **So:** `detect_fillers` and Remove Filler Words… read fillers only from a transcript whose
    marker serves `.fillers` (TR-2); for media with none, the sheet says filler removal needs a
    cloud transcript and offers the estimated re-transcribe (TR-2, TR-4). On-device captions are
    unchanged and filter nothing.
  - Risk accepted: a person with no AssemblyAI key has no filler removal. One speaker, one
    script, one Mac; a later engine that keeps fillers would be a new decision.
- **TR-8 — The caption filler vocabulary is: um, uh, hmm, mhm, uh-huh, ah, huh, hm, m, er, erm.**
  Recorded in CT-1, before its code (`FillerWords.assemblyAI`, `FillerWords.swift`).
  - **The sources, as read on 2026-10-22:** AssemblyAI's Universal-2 "Filler words" page
    (https://www.assemblyai.com/docs/filler-words, read through a search summary) lists the first
    nine. The older core-transcription page lists five of them (um, uh, hmm, mhm, uh huh). The
    current page (https://www.assemblyai.com/docs/pre-recorded-audio/filler-words) gives only "uh"
    and "um" as examples, and says `disfluencies` applies to Universal-3.5 Pro and Universal-2.
    AssemblyAI's Universal-3 Pro prompting material names er, erm, ah, hmm and mhm as fillers.
  - **No published list for the first model:** Universal-3.5 Pro, the first model the app
    requests, has no published list, so the nine words are documented for Universal-2 only, and
    no published list guarantees that captions equal those made before CT-1.
    `cloud_captions_live.py` row 22 records what the real service returns.
  - **The match:** a word is a filler when its text, lowercased, with leading and trailing
    punctuation and whitespace trimmed, is in the list. "uh huh" is matched by its two halves,
    and `uh-huh` as one token. Captions drop exactly these. The cache keeps every served word
    verbatim (R6-3). Another source's fillers (TR-7) are added by that source's own entry.
  - **Why:** these are the tokens AssemblyAI itself names as fillers for the models the app
    requests.
  - Risk accepted: a real "ah" or "er", or the letter "M", is dropped from captions. A filler the
    service returns outside this list is captioned until a later decision adds it.
- **TR-9 — Filler cut edges are the transcript's filler runs, widened to the Silero 32 ms grid
  within the words beside them, then snapped inward to the frame grid.** Recorded in CT-2,
  before its code (`FillerDetector.swift`, `detect_fillers`).
  - **The words:** a clip's words are its media's cached words that belong to it by R6-10 (start
    in `[in, in + content_length)`), sorted by `(start, end)`, milliseconds to ticks through
    `MediaTranscript.sourceTicks` (the end uses `max(start, end)`). A **run** is a maximal
    sequence of consecutive `FillerWords.isFiller` words in that order; its source span is
    `[first.start, max end)`.
  - **The neighbours:** `previousEnd` is the larger of `in` and the latest end of every
    non-filler word sorted before the run; `nextStart` is the smaller of `in + content_length`
    and the earliest start of every non-filler word sorted after it.
  - **The grid:** G = `MediaSpeech.chunkTicks` (512 samples at 16 kHz, absolute source time from
    0, the speech cache's own index). `start = max(floor(run.start / G)·G,
    ceil(previousEnd / G)·G)` and `end = min(ceil(run.end / G)·G, floor(nextStart / G)·G)`:
    outward to the grid so the whole filler goes, never into a neighbouring word. `end ≤ start`
    drops the run (too short).
  - **The frame grid:** each edge maps to project time through `MediaTranscript.project` (R6-10's
    door), then `SilenceDetector.snapUpToFrame` (start) and `snapDownToFrame` (end), inward as
    Remove Silences snaps; `end ≤ start` drops it (too short).
  - **A locked track:** a clip on a locked track gives no candidates, because
    `ripple_delete_ranges` neither splits nor shifts a locked track (`core/src/edit_time.rs`), so
    the filler would stay and everything else would slide. A track the snapshot cannot find
    counts as unlocked, as the nest walls do.
  - **What drops a candidate, whole:** a project span that overlaps (half-open, more than 0
    ticks) a non-filler word (`MediaTranscript.words(for:in:)`) of any OTHER clip on an unlocked
    track whose media's transcript serves `.captions` — in scope or not, because the ripple cuts
    every unlocked track; one that crosses a nest clip; one that crosses a transition wall
    (`SilenceDetector.overlapWalls`). Checked in that order, and dropped whole, never trimmed, so
    every kept edge is a grid edge. Kept spans are merged where they overlap or touch.
  - **Nothing else:** no probability is read, no padding or threshold applies; a reversed clip
    and a clip `Transcriber.jobs` refuses have no words.
  - Risk accepted: the cut is only as tight as the words' timings; an inward frame snap can leave
    up to a frame of a filler; speech on an unlocked track whose media has no transcript is not
    protected.
