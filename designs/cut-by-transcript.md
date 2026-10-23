# Road map "cut-by-transcript" — remove the ums and false starts on the words' timings

**Opened 2026-10-22** (CT-0, in the worktree `~/devel/framejob-tcut` on branch `transcript-cut`,
from `15d3545`, each phase merged into main after its gate), for issue #92. This road map's
decisions are TR-1 onwards, in `designs/spec/11-decisions/cut-by-transcript.md`.

## Goal

A person can say "remove the ums" and have the timeline cut on the words' own timings. Today the
pieces exist apart: transcription yields per-word times (the cloud words cached verbatim per
media under R6-3), Remove Silences cuts with `ripple_delete_ranges` on edges from the Silero VAD
cache, and nothing joins them — no op, tool, menu item or sheet removes words. As the owner
decided on 2026-09-30 (TR-3), there are two paths, split by who judges. **Fillers** are
deterministic: AssemblyAI reports them when asked (TR-1, TR-2), a detector finds them by their
spelling, and Clip ▸ Remove Filler Words… cuts them as Remove Silences cuts a silence (TR-4).
**False starts** are a judgement of meaning, so no pipeline picks them; the assistant may, when
the person asks, through a new `get_transcript` tool (TR-5). Captions look unchanged throughout.
#92's done-when is CT-2's proof: a known filler cut out of a fixture, its ranges read back
through `get_project`, the cut edges on the VAD grid.

## The owner's choices

**2026-09-30**, verbatim (#92's comment of that day):

> **Decided by the owner, 2026-09-30, and iced.** The design calls are made, but the work is not scheduled. When it is taken up, it is a road map in `designs/`, and each decision below gets its spec §11 entry first.
>
> 1. **Fillers come from `disfluencies: true` on every cloud request from then on.** The caption producers filter fillers out, so captions look unchanged. This amends R6-15, since the marker records the request.
>    - A transcript cached before the change is re-transcribed only when the person asks for filler removal on that media, and the estimate line shows the cost first.
>    - Whether the on-device engine reports fillers is unmeasured, so the road map opens with a spike. If it doesn't, filler removal is cloud-only and the sheet says so.
> 2. **Two paths, split by who judges:**
>    - **Fillers are deterministic:** a "Remove Filler Words…" command shaped like Remove Silences. It has a sheet, a candidate wash on the timeline, one `ripple_delete_ranges` undo step, and its own MCP tool.
>    - **False starts go to the assistant,** under AI-6 (W-9 as amended: no pipeline picks by meaning, but the assistant may on a person's request). It needs a new `get_transcript` tool returning a clip's words with timeline times; no tool exposes word timings today. The person asks, and the assistant proposes and makes ordinary undoable cuts.

And the owner's ask that took it up (2026-10-22): "#92 Cut by transcript".

## How it fits the tree

Every piece a phase builds on, as the tree stands at `15d3545`:

- **The words and their mapping.** `MediaTranscript.words(for:in:)`
  (`app/Sources/MediaTranscript.swift`) maps a media's cached words onto a clip (R6-10); its
  caption callers are where CT-1 drops fillers.
- **The cloud request.** `TranscriptOptions` and `TranscriptRequest`
  (`app/Sources/AssemblyAITranscript.swift`) are what is sent; neither has `disfluencies` today.
  `TranscriptStamp` (`app/Sources/TranscriptStamp.swift`) is the marker, and
  `MediaTranscript.isCurrent` (`app/Sources/MediaTranscript.swift`) is an equality test of a
  stamp against the cached one (R6-15), so a new key changes what is current unless CT-1's
  caption rule reads past it (TR-2). `CloudEstimate` (`app/Sources/CloudEstimate.swift`) is the
  cost line; `CloudTranscriber` (`app/Sources/CloudTranscriber.swift`) runs the upload, the job
  and the fetch.
- **The caption producers.** `CaptionPages.normalize` and `CaptionPages.cues`
  (`app/Sources/CaptionPages.swift`) and `CaptionLayout.place` (`app/Sources/CaptionLayout.swift`)
  turn words into pages; none of them may see a filler (TR-1).
- **Remove Silences, the shape to copy.** `SilenceDetector` (`app/Sources/SilenceDetector.swift`),
  `SilenceSheetController` (`app/Sources/SilenceSheetController.swift`), the candidate wash in
  `TimelineView+Candidates` (`app/Sources/TimelineView+Candidates.swift`) and `detect_silence`,
  the read half, in `app/Sources/AgentServer+Silence.swift`. `SileroVAD`
  (`app/Sources/SileroVAD.swift`, `chunkSamples` = 512 at 16 kHz, the 32 ms grid) and
  `MediaSpeech` (`app/Sources/MediaSpeech.swift`, the per-media cache under `cache/speech/`) give
  the grid CT-2's edges land on.
- **The cut.** `ripple_delete_ranges` (`core/src/edit.rs` l.125): several `[from, to]` pairs
  snapped, clamped, merged and cut right to left as one edit, one undo step. No new op (TR-4).
- **The assistant.** `AssistantToolTable.swift` withholds the cloud `transcribe` (AI-7), and
  `AssistantPrompt.swift` groups the tools the prompt names; CT-4 adds `get_transcript` there.
- **The on-device engine.** `SpeechEngine` (`app/Sources/SpeechEngine.swift`) runs
  `SpeechTranscriber` with `transcriptionOptions: []` and keeps no transcript cache; whether it
  reports fillers is CT-0's spike, and TR-7 (the on-device filler source) is its answer, owed.

## Phases

- **CT-0, the road map, TR-1…TR-6 and the filler spike.** No product code. TR-7, the on-device
  filler source, is owed: the spike's o2 row, run on the owner's own reading of its script,
  decides it before CT-2, the first phase that reads fillers. CT-1 does not depend on it.
- **CT-1, fillers on the cloud request (TR-1, TR-2):** `TranscriptOptions`/`TranscriptRequest`/
  `TranscriptStamp` gain `disfluencies` (`AssemblyAITranscript.swift`, `TranscriptStamp.swift`;
  an old marker with no key decodes as false). Every cloud request sends `disfluencies: true`. A
  caption run takes a current marker whatever its `disfluencies` value; a filler run needs true.
  One filler vocabulary, in a new file. `MediaTranscript.words(for:in:)`'s caption callers drop
  fillers, so captions stay byte-identical. Proved over `assemblyai_fake.py`. The live rows run
  only behind `--live` and are skipped by name without `RC_ASSEMBLYAI_KEY`.
- **CT-2, `detect_fillers` and the cut:** a pure detector, from the transcript's filler words to
  project ranges with their edges on the Silero 32 ms grid (`MediaSpeech`,
  `SileroVAD.chunkSamples`), frame-snapped as `SilenceDetector` snaps. The exact grid rule is
  TR-9, recorded before the code. `detect_fillers` is the read half
  (`AgentServer+Fillers.swift`, a row in `AgentCatalog+Audio.swift`), and `ripple_delete_ranges`
  makes the cut. This phase's proof is #92's done-when: it cuts a known filler out of a fixture,
  reads the ranges back through `get_project`, and checks the edges on the VAD grid.
- **CT-3, Clip ▸ Remove Filler Words…:** a new `FillerSheetController.swift`, shaped like
  `SilenceSheetController`. The candidate wash comes from `TimelineView+Candidates.swift`. Remove
  is one `ripple_delete_ranges` undo step. Media with no disfluent transcript get an estimate
  line (`CloudEstimate`) and a Transcribe button (TR-2), and the sheet shows a cloud-only note if
  TR-7 says so. The re-transcribe gets its MCP mirror, withheld from the assistant under AI-7.
  The phase adds a menu row in `AppDelegate+Menus.swift`, a screen in `designs/screens/` and a
  row in `docs/manual-checks.md`.
- **CT-4, `get_transcript` and false starts (TR-5):** an app-state tool that answers a clip's
  words in timeline times, with fillers flagged. It reads the current cloud cache when there is
  one, else runs the on-device engine over the clip's window, and never makes a network call.
  The phase adds the tool to its `AssistantPrompt.swift` group and an `AssistantToolTable.swift`
  row if one is needed. The proof is an `assistant_send` stand-in turn that calls
  `get_transcript` and then `ripple_delete_ranges`, with no paid call.
- **CT-5, the close:** `designs/adr/cut-by-transcript.md`, a `git mv` of this road map to
  `archive/`, its row in `archive/INDEX.md`, and residue filed as issues. #92 is closed.

## Decisions

TR-1… live in `designs/spec/11-decisions/cut-by-transcript.md`.

## Person checks

FIL-1 in `docs/manual-checks.md` (CT-3): a real narrated recording, the estimate
read, Transcribe pressed, the wash looked at, Remove, every cut played, one ⌘Z.
AS-10 (CT-4): with a real key and a real recording that holds a false start, the assistant
asked to take the false starts out names the words before it cuts, cuts only those, and one ⌘Z
undoes the cuts it made together (one `ripple_delete_ranges`, one undo step).

## CT-0 record

**What landed (2026-10-22):** this road map; TR-1…TR-6 in
`designs/spec/11-decisions/cut-by-transcript.md`, recorded before any spike code; the
Amended-by lines on R6-15 (by TR-1), AI-6 (by TR-5) and W-9 (by TR-5), with their index rows;
the filler spike, `tools/proof/filler_spike/` (`filler_spike_probe.swift`, `filler_spike.py`,
its `README.md`) and its section in `tools/proof/README.md`. TR-7 was not written (below).
No product code: nothing under `app/`, `core/`, `graphic/`, `mcp-proxy/` or `agent/` changed.

**The filler spike.** Run 2026-10-22 on macOS 26.5.1 (25F80), tree `15d3545` with CT-0's
uncommitted changes, through the app's own `Transcriber.extractAudio` and
`SpeechEngine.transcribe` (en-US installed; `transcriptionOptions: []`), once, on the final
instrument (the runner and probe as committed). The runner exited 2, `SPIKE INCOMPLETE`, naming
o2 alone ("the owner's sample is absent (no file in tools/proof/media/filler-sample/)"); f1,
f2, f3 and o1 ran, and `answers.json`'s verdict is **`tts-only`**, `reported_in`
`["f1", "f2"]`, with the counts below (the same as an earlier run of the instrument before o2
was added). The final instrument's selftest scored 13/13; `--mutant keep-punctuation` failed K,
O, f2 silences, f1 scripted and o2 scripted, `--mutant replaced-as-kept` failed R and O, and
`--mutant o2-ignored` failed V1 and V2, each exit 1.

| Row | Audio | Words recognised | `filler_count` | `filler_tokens` | The 8 scripted fillers |
|---|---|---|---|---|---|
| f1 | `say`, F1 as written, 13.066 s | 27 | 6 | um 3, uh 3 | 6 kept; "er" replaced by "or"; "hmm" dropped |
| f2 | `say`, F1 with `[[slnc 300]]` around each filler, 15.429 s | 27 | 7 | um 3, uh 2, er 1, hmm 1 | 7 kept; the second "uh" (before "well") dropped |
| f3 | `say`, F1 without its fillers (the control), 8.117 s | 20 | 0 | — | none scripted; 100 % of the script recognised |
| o1 | `tools/proof/media/owner-sync/record.aifc`, 165.002 s (1 ch, 48 kHz, 24-bit) | 6 | 0 | — | none scripted |

o1's format is `afinfo`'s (1 ch, 48000 Hz, 24-bit big-endian signed integer, 165.002667 s).
`owner-sync-2/record.aifc` is byte-identical to o1's file (`md5` of both
`8c36c7127aa1b0e167b56d28414605d2`, 2026-10-22) and is not a row. o1's raw words stayed in the
runner's memory; only the counts above were written.

**What the answer means.** In synthetic speech the engine kept "um" and "uh" as words: 6 of 6
in F1 and 5 of 6 in F2. It kept "er" and "hmm" only in F2, with silence around them; in F1 "er"
came back as "or" and "hmm" was dropped. In the one real recording it reported none, but that 0
is weak evidence either way: nobody scripted o1, so a 0 cannot tell a dropped filler from one
never said, and o1 recognised only 6 words in 165 s (`ffmpeg`'s `volumedetect` read its mean
level at −46.1 dB and its peak at −10.2 dB), so most of it held no speech the engine heard. Why
the synthetic fillers were kept was not measured. The verdict is `tts-only`.

**TR-7 was not written.** The owner was shown this result on 2026-10-22 and chose to record a
sample: about 30 s of the owner reading the spike's fixed script (`O2_SCRIPT`, eight fillers:
um 3, uh 3, er 2) into `tools/proof/media/filler-sample/` (gitignored; the instructions are
`tools/proof/filler_spike/README.md`'s "Recording the owner's sample"). A §11 entry is not
re-litigated, so a cloud-only TR-7 written now could not be revised by that sample. The runner
gained the row o2 for it the same day: aligned against the script like f1, skipped by name
while the folder holds no file, and the real-speech row of the verdict once f1 and f2 have run
(o2 reported a filler: `reports-real`; o2 reported none: `does-not-report`; o2 absent: the o1
rule that gave `tts-only`, as the spike's README lists it). Its
selftest now scores 13/13 (K, D, R, Z, O for o2's alignment, V1–V4 for the verdict, and four
fixture-text rows); `--mutant keep-punctuation` fails K, O and the three fixture-text rows that
read a filler, `--mutant replaced-as-kept` fails R and O, and `--mutant o2-ignored` fails V1 and
V2, each exit 1. o2 has not run: the sample does not exist yet.

**The owner's sample, and TR-7** (2026-10-22, after CT-1's merge). The owner recorded the
script (`filler-sample/test-recording.aifc`, read in place, gitignored); `python3
tools/proof/filler_spike/filler_spike.py` exited 0 with every row run: f1 6 of 8 and f2 7 of 8
as before, f3 0 (script 100 %), o1 0 (6 words), and **o2: 59 words, 98.3 % of the script's other
words recognised, 1 of 8 fillers kept** (the first "um"; um 2, uh 3 and er 2 dropped). The
verdict printed `reports-real` (any kept filler counts). Shown that, the owner chose
"Cloud-only (Recommended)": TR-7 records filler removal as cloud-only.
No `CLAUDE.md` edit is owed by CT-0: no file's role changed and no rule was added.

## CT-1 record

**What landed (2026-10-22):** TR-8 (the caption filler vocabulary) in
`designs/spec/11-decisions/cut-by-transcript.md`, recorded before the code, with its index row
and the Lines cells. `TranscriptOptions.disfluencies` (default true, its CodingKey and encode
line) and `TranscriptRequest`'s always-written `disfluencies` (`AssemblyAITranscript.swift`):
the default wire body is exactly `audio_url`, `disfluencies: true`, `speaker_labels`,
`speech_models`. `TranscriptStamp.disfluencies` (encoded; absent decodes false),
`TranscriptUse`, `TranscriptStamp.serves(_:for:)` and `TranscriptOptions.init(from:)` (absent
false), in `TranscriptStamp.swift`. A new marker's outer keys are `disfluencies,
keyterms_prompt, language_code, provider, source, speaker_labels, speech_models`, and a new
cache file's `requested` gains `"disfluencies":true`, sorted first. `FillerWords.swift` (new):
`FillerWords.assemblyAI`, `normalized`, `isFiller` and `MediaTranscript.captionWords(for:in:)`.
The four call sites: `MediaTranscript.isCurrent` and `CloudEstimate.fate`'s `current` through
`serves(_:for: .captions)`, `CloudTranscriber`'s keyless admission likewise and its step (4)
through `captionWords`, and the sheet's `sampleWords()` through `captionWords`. No format
change, no op, no tool and no FFI change; `.fillers` has no product caller yet (CT-2 is its
first). The instruments: `filler_words_probe.swift` and `filler_words_proof.py` (new),
`assemblyai_fake.py`'s `disfluent_words`, the re-pins and KL row in `cloud_captions_probe.py`,
rows 2, 4, FD and FL in `cloud_captions_proof.py`, live row 22 in `cloud_captions_live.py`
(with `cloud_live_ledger.py`'s `refusal`/`reserve` taking `seconds=PLANNED_SECONDS`), and S6's
filler row in `word_captions_sheet_probe.swift`; `tools/proof/README.md`'s "Cut by transcript
CT-1" section lists them.

**TR-8's sources, as read on 2026-10-22** (the orchestrator's reading; the designer could not
read the page): the current page, https://www.assemblyai.com/docs/pre-recorded-audio/filler-words,
gives no exact list, only "uh" and "um" as examples, and says `disfluencies` applies to
Universal-3.5 Pro (English, Spanish, German, French, Portuguese, Italian) and Universal-2
(English only); a search summary of the Universal-2 page,
https://www.assemblyai.com/docs/filler-words, gives nine — um, uh, hmm, mhm, uh-huh, ah, huh,
hm, m; the older core-transcription page lists five — um, uh, hmm, mhm, uh huh; AssemblyAI's
Universal-3 Pro prompting material names er, erm, ah, hmm and mhm. The app's first model is
Universal-3.5 Pro, for which no list is published, so the eleven words are a choice and not a
guarantee; live row 22 records what the real service returns.

**The runs** (2026-10-22, macOS 26.5.1, the worktree on `7ff117f` with CT-1's uncommitted
changes, each on the final instrument):

| Command | Result |
|---|---|
| `make typecheck` | 0 errors, the 4 baseline warnings |
| `python3 tools/proof/filler_words_proof.py` | 10/10 (B0, W1, D1, D2, S1, S2, E1, V1, C1, C2), exit 0 |
| `env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_probe.py` (whole) | 876/876, one row skipped by name (`work/cloud_spike/fixtures/late.mov` is not on this host — C0's untracked late-audio fixture, as before CT-1), exit 0 |
| `… cloud_captions_probe.py --only keyless --mutant keyless-strict-marker` | caught: 43/44, the one failure KL's no-`disfluencies` row, exit 1 (the probe's mutant convention: rows failed) |
| `python3 tools/proof/word_captions_chrome.py` | 50/50, S6's filler row among them, exit 0 |
| `make app-debug && env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py` (Debug) | 225/225, FD and FL among them; `grep "Frame Job: "` empty in all five instances' logs, exit 0 |
| `make gate` | PASS: names, typecheck (its 4 baseline warnings), test and app ran and passed; fmt and lint skipped as byte-identical (no Rust changed) |
| `RC_PROOF_APP=release env -u RC_ASSEMBLYAI_KEY python3 tools/proof/cloud_captions_proof.py` (Release, after the gate's `make app`) | 225/225, FD and FL among them; `grep "Frame Job: "` empty in all five instances' logs, exit 0 |
| `RC_PROOF_APP=release python3 tools/proof/cloud_captions_proof.py --live` (PAID) | 44/44, the live rows' 42 checks (`LIVE_ROW_COUNT` 42) and nothing skipped; `grep "Frame Job: "` empty in L0's and L1's logs, exit 0 |

An earlier pass of the targeted probe sections scored 323/325: SP3 and SP4·off failed because
the probe file, built against B46's baseline tree with `-D CLOUD_PROBE_BEFORE_SPEAKERS`, now
named `disfluencies` and `serves`, which that tree lacks. `makeOptions`' new argument and the
stamp mode's `serves` answers were put behind that flag, as the file's other post-B46 lines
are, and the re-run scored 328/328. No row any section held before CT-1 fails.

**The mutants.** `filler_words_proof.py --mutant NAME`, each anchor asserted once, exit 0 when
caught; every one was caught:

| Mutant | Must fail | Failed (score) |
|---|---|---|
| `fillers-kept` | C1 C2 | C1 C2 (8/10) |
| `captions-need-disfluent` | S1 S2 E1 | S1 S2 E1 (7/10) |
| `fillers-take-any-marker` | S1 | S1 (9/10) |
| `request-omits-disfluencies` | W1 | W1 (9/10) |
| `legacy-marker-key-required` | D2 S2 | D2 S2 E1 (7/10) |
| `legacy-requested-key-required` | D1 | D1 (9/10) |
| `case-sensitive-fillers` | V1 | V1 C1 C2 (7/10) |
| `estimate-strict-marker` | E1 | E1 (9/10) |

and `cloud_captions_probe.py`'s `keyless-strict-marker`, above: nine.

**Live row 22, and the spend.** `RC_ASSEMBLYAI_KEY` was present in the environment the
implementing agent inherited (it was expected to be absent, and the run to skip by name), so the
live run made its paid calls: row 20's 11 s round trip and row 22's 16 s, 27 billed seconds at
$0.21 an hour, **$0.0016** (row 22 alone $0.0009); the live ledger
(`work/cloudlive/ledger.json`) closed with nothing owed at $0.0029 over 49 planned seconds, four
reservations of which two (20 and 22, both `deleted`) count against `MAX_TRANSCRIPTIONS`' six
(20d `no_transcript`, 21 `no_upload`). The real service accepted `disfluencies: true` (the
submit answered 200) on both requests. On `fillers.aiff` (`say` of F2, the spike's text with
silence around each filler) it served 27 tokens, and the ones that are not script words were
**um 3, uh 2, er 1, hmm 1** — every one a scripted filler and every one in TR-8's list: seven
of the script's eight fillers (um 3, uh 3, er 1, hmm 1), one "uh" not returned (which one was
not recorded). None of them reached a cue. No other non-script token came back. Deviation:
row 22 reads `disfluencies: true` from the cache's `requested`, the marker and the submit's
200, not from the submit BODY, because the live client logs no request body; rows 2 and FD
check the wire body itself against the fake.

**Accepted, harmless:** the janitor's success re-encodes a cache file's header (`File.encoded()`,
R6-4's `remote_deleted` rewrite, which it already did before CT-1), so on a file written before
CT-1 it now also writes `"disfluencies":false` into `requested`. That is the old request's true
value and reads the same as an absent key; the `words` bytes are untouched (R6-3) and the marker
is not rewritten, so `serves` answers the same for captions and for fillers. It happens only
when a delete was still owed on a pre-CT-1 cache file. Not an issue.

**Owed:** TR-7, from CT-0, before CT-2 (the owner's scripted sample). `app/CLAUDE.md`'s map
entries were applied at merge. Review: pass, three nits — two applied at merge (this deviation
sentence; the janitor note's heading), one left (`cloud_captions_live.py`'s `billed` computed
twice: a tidy in a paid instrument that cannot be re-run free).

## CT-2 record

**What landed (2026-10-22):** TR-9 (filler cut edges) in
`designs/spec/11-decisions/cut-by-transcript.md`, recorded before the code, with its index row
and the Lines cells. `FillerDetector.swift` (new): `read(from:clips:)`, the one seam that touches
the document (the edited project's snapshot, the selection, `mediaURLs()`, the transcript cache),
and the pure `runs`, `gridded`, `placed` and `detect`; the scope's transcripts come through
`fillersFile` (`transcriptFile(…, use: .fillers)`), the neighbours' through `transcriptFile(…,
use: .captions)`, and `onUnlockedTracks` keeps a locked track's clips out. `AgentServer+Fillers.swift`
(new): `detect_fillers`, an app-state tool on the main thread that edits nothing, answering
`ranges`, `count`, `removes`, `scope`, `clips`, `fillers`, `dropped`, `needs_transcript`,
`locked`, `project`, and `skipped`/`note` when there is something to say. Its catalog row is
the fourth in `AgentCatalog+Audio.swift` (`clips` only), its handler row and the count words in
`AgentServer.swift`, `AgentCatalog.swift` and `AgentServer+Gate.swift`, and its topic in
`AssistantPrompt.searchTopics`' audio row. Two pure moves to share one rule: `nestExtents(in:)`
out of `SilenceDetector.read` into `SilenceDetector+Walls.swift`, and
`MediaTranscript.project(_:in:)` from `private` to internal (R6-10's one door). No Rust, header,
FFI, op or format change. The instruments: `fillers_probe.swift` and `fillers_proof.py` (new);
the tool counts in `op_argument_proof.py` (95), `phase9_proof.py`, `recording_probe.py` and
`recording_proof.py` (thirty-four app-state tools); `tools/proof/README.md`'s "Cut by transcript
CT-2" section. Spec §7.9a, §7.9c, §7.4 and the README's tool table name the tool.

**The runs** (2026-10-22, macOS 26.5.1, the worktree on `37b10f7` with CT-2's uncommitted
changes, each on the final instrument; every proof under `env -u RC_ASSEMBLYAI_KEY`, nothing
paid):

| Command | Result |
|---|---|
| `make typecheck` | 0 errors, the 4 baseline warnings |
| `fillers_proof.py --only P0,…,P9` | 10/10, exit 0 |
| `assistant_prompt_proof.py --probe` | 14/14, F4 among them, exit 0 |
| `spec_index_proof.py` | 180/180, exit 0 |
| `make app-debug && fillers_proof.py` (Debug) | 17/17 (P0–P9, M0–M6), exit 0 |
| `make gate` | PASS: names, typecheck (its 4 baseline warnings), test and app ran and passed; fmt and lint skipped as byte-identical (no Rust changed) |
| `RC_PROOF_APP=release fillers_proof.py` (Release, after the gate's `make app`) | 17/17, exit 0; M1 [[1460000, 1780000]] with words ["um,", "Uh", "er"], M2 clips [0, 1460000) in 0 and 1460000 in 1780000, undo back to one clip |
| `op_argument_proof.py <dir>/agent.sock` (Release) | 165/165, exit 0 |
| `phase9_proof.py <dir>/agent.sock` (Release) | 236/236, exit 0; `grep "Frame Job: "` on that instance's log empty |
| `recording_probe.py --only catalog` | 31/31, exit 0 |
| `python3 -m py_compile tools/proof/recording_proof.py` | exit 0 (the proof itself needs a Screen Recording grant) |

**The mutants.** `fillers_proof.py --mutant NAME` (probe rows only), each anchor in
`FillerDetector.swift` asserted once, exit 0 when caught; every one was caught:

| Mutant | Must fail | Failed (score) |
|---|---|---|
| `grid-nearest` | P1 | P1 P6 (8/10) |
| `no-neighbour-bound` | P2 | P2 P5 (8/10) |
| `no-run-merge` | P3 | P3 (9/10) |
| `frame-outward` | P4 | P4 P6 (8/10) |
| `no-word-conflict` | P6 | P6 (9/10) |
| `no-walls` | P7 | P7 (9/10) |
| `fillers-from-any-marker` | P8 | P8 (9/10) |
| `no-lock-filter` | P9 | P9 (9/10) |

**Deviation:** the scope's `use: .fillers` call is its own one-line door,
`FillerDetector.fillersFile(for:url:in:)`, which `read` calls and P8 calls, so the
`fillers-from-any-marker` mutant's anchor sits where a probe row can reach it; a probe cannot
build the `ProjectDocument` `read` takes.

**Owed:** the root `CLAUDE.md`'s "ninety-four" (Rules) → "ninety-five" and `detect_fillers` in
"Verifying a build"'s app-state list; `app/CLAUDE.md`'s map entries for `FillerDetector.swift`
and `AgentServer+Fillers.swift` and its two tool counts. A real recording's filler cut stays a
person's check (TR-6) until CT-3's sheet; CT-3 owes the menu, the sheet, the wash and its
manual-checks row.

## CT-3 record

**What landed (2026-10-23):** TR-10 in `designs/spec/11-decisions/cut-by-transcript.md`,
recorded before the code, with AI-7's "Amended 2026-10-22, by TR-10" line, the index rows and
the Lines cells. `FillerTranscription.swift` (new): the one media's request
(`options(for:)` — the marker's language, speakers and vocabulary, the shipped models,
`disfluencies: true`), `refresh = true`, `jobs(for:in:urls:)` and `estimate(jobs:media:
cacheDirectory:)`, shared by the sheet and the tool. `FillerSheetController.swift` (new):
Clip ▸ Remove Filler Words…, `SilenceSheetController`'s shape without controls — the
summary, the joined note (selection scope, dropped fillers, locked clips, nothing read, no key,
nowhere to cache, the last run's error), Remove enabled only with spans and no run, the
`candidateSpans` wash set in `refresh()` and cleared in `viewDidDisappear` (which also stops a
run), one `ripple_delete_ranges` named "Remove Filler Words", `runStarted`/`runEnded`, and
`removeFillerWordsCommand`/`validateFillerAction` at its foot.
`FillerSheetController+Transcribe.swift` (new): the TR-7 section's rows (name, `describe`
estimate with the `rateSentence` tooltip, a `.secondary` Transcribe button that is Stop on the
running row), the button's state, and the `CloudTranscriber.run` a press starts.
`AgentServer+Fillers.swift`: `transcribe_for_fillers {media}`, off main, refusing in the
spec's order and answering `ready` with `cloudFields`; `detect_fillers`' note names it.
Wiring: the menu item after Remove Silences… (no key), the frozen forward and validator line
in `EditorViewController.swift`, `UIMenuTable`'s `.sheet` row, `inventory.json`'s selector
and site, the handler row and `productOffMainTools` entry in `AgentServer.swift` (the
`agent_open_proof.py` anchor line untouched), the catalog row after `detect_fillers`, the count
words (ninety-six tools, thirty-five app-state) and `AssistantToolTable`'s withheld row. No
Rust, header, FFI, op or format change. The instruments: `filler_sheet_probe.swift` and
`filler_sheet_proof.py` (new); `fillers_proof.py` M4, `op_argument_proof.py` (96),
`phase9_proof.py`, `recording_probe.py`, `recording_proof.py`, `assistant_session_proof.py`
and `assistant_lane_probe.swift`'s fifth L4 case; `tools/proof/README.md`'s "Cut by transcript
CT-3" section; the screen `designs/screens/14b-remove-filler-words-sheet.md`; FIL-1 and CH-4 in
`docs/manual-checks.md`. Spec §7.9a, §7.9c, §7.4, §9 and the README name the sheet and tool.

**The runs** (2026-10-22/23, macOS 26.5.1, the worktree on `a4bcbd2` with CT-3's uncommitted
changes, each on the final instrument; every app proof under `env -u RC_ASSEMBLYAI_KEY`,
nothing paid):

| Command | Result |
|---|---|
| `make typecheck` | 0 errors, the 4 baseline warnings |
| `swift_build.py typecheck filler_sheet_probe.swift` | exit 0 |
| `filler_sheet_proof.py --only S0,…,S7` | 8/8, exit 0 |
| `capture_spike/inventory.py --check` | 5/5, exit 0 |
| `spec_index_proof.py` | 180/180, exit 0 |
| `make app-debug && filler_sheet_proof.py` (Debug) | 15/15, exit 0 |
| `fillers_proof.py --only M0,M1,M4` (Debug) | 3/3, exit 0 |
| `make gate` | PASS (names, typecheck, test — `assistant_lane_proof.py`'s L4 with its fifth case among it — and app ran; fmt and lint skipped, no Rust changed) |
| `v2_menu.py --only H` | 5/5, exit 0 (107 rows, `removeFillerWords:` among them) |
| `RC_PROOF_APP=release filler_sheet_proof.py` | 15/15, exit 0; T1 one submit with `disfluencies` and `speaker_labels` true, then [[1460000, 1780000]]; T5 "1 cut · removes 00:00:00:16", the wash on the timeline only while the sheet is up |
| `RC_PROOF_APP=release fillers_proof.py` | 17/17, exit 0 |
| `op_argument_proof.py <dir>/agent.sock` (Release) | 166/166, exit 0 |
| `phase9_proof.py <dir>/agent.sock` (Release) | 236/236, exit 0; `grep "Frame Job: "` on that instance's log empty |
| `recording_probe.py --only catalog` | 31/31, exit 0 |
| `python3 -m py_compile tools/proof/recording_proof.py` | exit 0 |
| `RC_PROOF_APP=release assistant_session_proof.py` | 13/13, exit 0 (stand-in server, no spend) |
| `RC_PROOF_APP=release screens.py --only 14b-remove-filler-words-sheet` | 6/6, 4 captures, 0 new problems |

**The mutants.** `filler_sheet_proof.py --mutant NAME` (probe rows only), each anchor asserted
once, exit 0 when caught; every one was caught:

| Mutant | Must fail | Failed (score) |
|---|---|---|
| `options-drop-request` | S4 | S3 S4 (6/8) |
| `estimate-no-refresh` | S3 | S3 S4 (6/8) |
| `no-wash` | S1 | S1 S2 (6/8) |
| `wash-kept` | S2 | S2 (7/8) |
| `first-span-only` | S2 | S2 (7/8) |
| `remove-always-enabled` | S3 | S3 S7 (6/8) |
| `remove-live-during-run` | S7 | S7 (7/8) |
| `transcribe-without-key` | S3 | S3 (7/8) |
| `not-withheld` | S6 | S6 (7/8) |

**Deviations:** `mediaRows` is an internal `var`, not `private(set)`, because the rows are
built in `FillerSheetController+Transcribe.swift` and Swift's `private(set)` reaches only its
own file; likewise the run's `cloud`, `token`, `lastError`, `runnable` and a `tornDown` flag
(set by the teardown so a run answering after the sheet has gone cannot put the wash back).
The targeted `fillers_proof.py --only M0,M4` was run as `--only M0,M1,M4`, since M4 reads M1's
session. Left alone, as the brief's out-of-scope list says: the undo name of the agent's
`ripple_delete_ranges` ("Remove Silences").

**Owed:** the root `CLAUDE.md`'s "ninety-five" (Rules) → "ninety-six" and
`transcribe_for_fillers` after `detect_fillers` in "Verifying a build"'s app-state list;
`app/CLAUDE.md`'s map entries for `FillerSheetController.swift`,
`FillerSheetController+Transcribe.swift` and `FillerTranscription.swift`, and its tool counts.
FIL-1 is the person's check of a real recording's cut.

## CT-4 record

**What landed (2026-10-23):** TR-11 in `designs/spec/11-decisions/cut-by-transcript.md`,
recorded before the code, with AI-16's "Amended 2026-10-23, by TR-11" line, the index rows
and the Lines cells. `TranscriptReader.swift` (new): the cache door `cached(for:url:in:)`
(`FillerDetector.transcriptFile(…, use: .captions)`, with `fillersReported` from
`fillersFile`), the pure mapping `cloudWords` (R6-10's `MediaTranscript.words(for:in:)`) and
`deviceWords` (`Transcriber.project`, a run at or past the clip's end dropped), both sorted by
(start, end, source order) and flagged by `FillerWords.isFiller`, and `recognize`, the
on-device run (`Transcriber.transcribe`'s model questions, `extractAudio`, then
`SpeechEngine.transcribe`, the WAV removed on every exit). `AgentServer+Transcript.swift`
(new): `get_transcript {clip, language?}`, off main, reading `AgentLane.shared.callCancel`
first and linking the on-device token with `stop?.onCancel { token.cancel() }`, the clip, its
job and the cache read in one `onMain` hop, refused in TR-11's order and answering TR-11's
keys. `AgentServer+Captions.swift`: `checkSpelling(of:)` and `transcriptionLanguage(_:)`
internal, bodies unchanged. Wiring: the catalog row after `transcribe` in `captionTools()`;
the handler row and `productOffMainTools` entry in `AgentServer.swift` (the
`agent_open_proof.py` anchor line untouched); the count words (ninety-seven tools, thirty-six
app-state) in `AgentCatalog.swift`, `AgentServer+Gate.swift` and `AgentServer.swift`;
`AssistantSession.cancel()`'s comment. `AssistantPrompt.swift`: the "Cutting words:" system
paragraph after the Captions and Graphics one, and the captions search topic with
`get_transcript` (guide 1486 of 1500, system 3134 of 6000). No `AssistantToolTable.swift` row
(TR-11). No Rust, header, FFI, op or format change. The instruments: `transcript_probe.swift`
and `transcript_proof.py` (new); `op_argument_proof.py` (97), `phase9_proof.py`,
`recording_probe.py` (the app-state list and 7b's last fifteen names) and
`recording_proof.py`; `tools/proof/README.md`'s "Cut by transcript CT-4" section; AS-10 in
`docs/manual-checks.md`. Spec §7.9a, §7.9b, §7.9c, §7.4 and the README name the tool.

**The runs** (2026-10-23, macOS 26.5.1, the worktree on `b8586cf` with CT-4's uncommitted
changes, each on the final instrument; every app proof under `env -u RC_ASSEMBLYAI_KEY`,
nothing paid):

| Command | Result |
|---|---|
| `make typecheck` | 0 errors, the 4 baseline warnings |
| `swift_build.py typecheck transcript_probe.swift` | exit 0 |
| `transcript_proof.py --only P0,P1,P2,P3` | 4/4, exit 0 |
| `assistant_prompt_proof.py --probe` | 14/14, exit 0 (F6: system 3134/6000, guide 1486/1500) |
| `spec_index_proof.py` | 180/180, exit 0 |
| `make app-debug && transcript_proof.py` (Debug) | 13/13, exit 0; no host skip |
| `make gate` | PASS (names, typecheck, test and app ran; fmt and lint skipped, no Rust changed) |
| `RC_PROOF_APP=release transcript_proof.py` | 13/13, exit 0; G1 the eight `mapped` words with "um,", "Uh", "er" flagged and no AssemblyAI request; G5 17 on-device words, "quick" and "fox" among them; A1 clips (0, 360000, 0) and (360000, 2040000, 960000), one undo back to (0, 3000000, 0); A3 stopped at 2012 ms, answered at 2127 ms with "The transcription was cancelled." |
| `op_argument_proof.py <dir>/agent.sock` (Release) | 167/167, exit 0 |
| `phase9_proof.py <dir>/agent.sock` (Release) | 236/236, exit 0; `grep "Frame Job: "` on that instance's log empty |
| `recording_probe.py --only catalog` | 31/31, exit 0 |
| `python3 -m py_compile tools/proof/recording_proof.py` | exit 0 |
| `RC_PROOF_APP=release assistant_session_proof.py` | 13/13, exit 0 (T2: 95 tools, `get_transcript` among them; stand-in server, no spend) |

**The mutants.** `transcript_proof.py --mutant NAME`, each anchor asserted once, exit 0 when
caught; every one was caught:

| Mutant | Must fail | Failed (score) |
|---|---|---|
| `no-filler-flag` | P1, P2 | P1 P2 (2/4) |
| `unsorted` | P1 | P1 P2 (2/4) |
| `device-past-clip-end` | P2 | P2 (3/4) |
| `fillers-reported-any` | P3 | P3 (3/4) |
| `stale-cache-read` | P3 | P3 (3/4) |
| `no-transcript-stop` | A3 with `LATE` | A3 (1/2, on the Debug copy built by `tree_copy.build_app` in 38 s): stopped at 2029 ms, answered at 49052 ms — the hour recognised to its end |

**Deviations:** `recording_probe.py`'s 7b (the catalog's last names in order) was widened from
fourteen to fifteen with `get_transcript` after `transcribe` in `FILE_GROUP_ORDER`: the spec's
catalog row lands between `transcribe` and `export_captions`, which the old list did not
allow, and #326's `export_status` was added the same way. The `get_transcript` refusal for a
clip `Transcriber.jobs` refuses falls back to "it plays no speech" only if the jobs answer
neither a job nor a problem, which they never do for one clip. In mutant mode
`no-transcript-stop` also runs G5 in the mutant app, as A3's host check.

**Owed:** nothing in `CLAUDE.md` (the root's count and app-state list and `app/CLAUDE.md`'s
map entries and counts were applied at merge). Review: pass, one nit applied at merge (AS-10's
expectation: one ⌘Z undoes the assistant's cuts together, as one `ripple_delete_ranges`); no paid
`assistant_prompt_proof.py --live` run, since its six live asks touch nothing this paragraph is
about and a real model's false-start judgement is AS-10's. AS-10 is the person's check of a real false start with a real key. For
CT-5's residue issues: a `from`/`to` window on `get_transcript` for a long clip's large answer,
and the on-device recognition repeated on every call (TR-11's risks).

## CT-5 record

Not started.
