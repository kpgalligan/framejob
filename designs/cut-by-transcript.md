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
  recorded as a TR entry before the code. `detect_fillers` is the read half
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

None yet.

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

**Owed:** TR-7, the on-device filler source, decided by `python3
tools/proof/filler_spike/filler_spike.py` run on the owner's sample, before CT-2, the first
phase that reads fillers. Under `reports-real` two owner questions come first: should
on-device captions filter fillers too (a visible change), and what shape should an on-device
filler path take? CT-1 (cloud disfluencies) does not depend on it and proceeds meanwhile.
No `CLAUDE.md` edit is owed by CT-0: no file's role changed and no rule was added.

## CT-1 record

Not started.

## CT-2 record

Not started.

## CT-3 record

Not started.

## CT-4 record

Not started.

## CT-5 record

Not started.
