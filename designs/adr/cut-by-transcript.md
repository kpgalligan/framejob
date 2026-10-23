# Cut by transcript: filler words cut on their timings, false starts through the assistant (road map "cut-by-transcript")

- **Status:** Built and closed 2026-10-23, for #92. Each phase was one litecode pipeline with its own review, worked in `~/devel/framejob-tcut` on branch `transcript-cut` and merged into main alone after its gate (TR-6):
  - CT-0, the road map, TR-1…TR-6 and the on-device filler spike (`7ff117f`)
  - CT-1, fillers on every cloud request, filtered out of captions (TR-1, TR-2, TR-8) (`f8e5a4b`)
  - TR-7, filler removal cloud-only, after the spike's o2 row on the owner's sample (`37b10f7`)
  - CT-2, `detect_fillers` and the cut (TR-9) (`a4bcbd2`)
  - CT-3, Clip ▸ Remove Filler Words… and `transcribe_for_fillers` (TR-10) (`b8586cf`)
  - CT-4, `get_transcript` and false starts through the assistant (TR-11) (`2f9fda8`)
  - CT-5, the close: this record (the commit that moved the original to `archive/`)
  - After the close, the residue batch: #333's toll (`f77d154`) and step name (TR-12, `71c6f7c`), #331's window (TR-13, `2d42d85`), #332's on-device cache (TR-14, `32db363`)
- **Original:** `archive/cut-by-transcript.md` is the full record. It has no section numbers, so it is cited by its own headings: "orig CT-2" is its "CT-2 record" section.
- **Spec decisions:** TR-1..TR-14 in spec §11 (`designs/spec/11-decisions/cut-by-transcript.md`). They stay binding, and where the original words them differently, §11's text wins:
  - TR-1: fillers come from AssemblyAI's `disfluencies: true` on every cloud request from CT-1 on, the marker records it, and the caption producers never see a filler, so captions stay byte-identical; road map 6's refusal superseded.
  - TR-2: a transcript cached before CT-1 stays current for captions; a filler run needs a `disfluencies` marker, and the re-transcribe is the person's ask on that media after the `CloudEstimate` line.
  - TR-3: two paths, split by who judges: fillers are deterministic, false starts a judgement of meaning.
  - TR-4: Remove Filler Words… is shaped like Remove Silences: a sheet, a candidate wash, one `ripple_delete_ranges` undo step and the read-half tool `detect_fillers`; no new op, no format change.
  - TR-5: false starts go to the assistant on the person's ask, read through the app-state tool `get_transcript`, never fetched over the network.
  - TR-6: the working arrangement: the `transcript-cut` worktree, each phase gated and merged alone, synthetic fixtures and the fake AssemblyAI, paid calls only behind their flags, owner media read in place.
  - TR-7: filler removal is cloud-only: on the owner's scripted sample the on-device engine kept 1 of 8 fillers.
  - TR-8: the caption filler vocabulary, um, uh, hmm, mhm, uh-huh, ah, huh, hm, m, er, erm, matched lowercased with edge punctuation trimmed, and its sources as read on 2026-10-22.
  - TR-9: filler cut edges: a run of fillers widened outward to the 32 ms Silero grid but never past the neighbouring words, snapped inward to frames; a locked-track clip gives none; a candidate over another clip's word, a nest or a transition wall dropped whole.
  - TR-10: Clip ▸ Remove Filler Words… has no tuning controls, makes one step named "Remove Filler Words", and its Transcribe re-transcribes one media with its previous request plus fillers; the mirror `transcribe_for_fillers {media}` is always withheld from the assistant.
  - TR-11: `get_transcript {clip, language?}`, one clip's words in timeline ticks with TR-8's `filler` flag, from the cached transcript or this Mac's recogniser, never the network, no cache written; off main and reached by the assistant's Stop; the prompt's false-start paragraph.
  - TR-12: an agent's `ripple_delete_ranges` names its undo step "Ripple Delete", whatever it cuts; the sheets keep their own names; no caller-passed name.
  - TR-13: `get_transcript` takes optional `from`/`to`, answers the words that overlap the window (an edge word whole), refuses an empty window and one outside the clip by name, and its on-device run hears the window plus 2 s each side.
  - TR-14: an on-device answer is cached in the package's `cache/device-transcripts/`, per media and language, keyed by the source stamp, the OS version and a format version; a call inside a stored run answers from it; nothing stored after a cancel; read by `get_transcript` alone.
  - Amended: R6-15 (by TR-1); AI-6 and, through it, W-9 (by TR-5); AI-7 (by TR-10); AI-16 (by TR-11); TR-11 (by TR-13, TR-14).

## Context

#92 asked that a person can say "remove the ums" and have the timeline cut on the words' own timings. The pieces existed apart: the cloud words were cached per media (R6-3), Remove Silences cut with `ripple_delete_ranges` on the Silero VAD grid, and nothing joined them. On 2026-09-30 the owner decided the design and iced it (#92's comment of that day, quoted verbatim in the original): fillers from `disfluencies: true` on every cloud request, filtered out of captions, with a re-transcribe of an older cache only on the person's ask and after the estimate; a spike on whether the on-device engine reports fillers, with filler removal cloud-only if it does not; and two paths split by who judges, a "Remove Filler Words…" command shaped like Remove Silences for fillers, and the assistant through a new `get_transcript` for false starts. On 2026-10-22 the owner took it up: "#92 Cut by transcript". (orig "Goal", "The owner's choices")

## Decisions

- **Filler removal is cloud-only (TR-7).** CT-0's spike ran the app's own `SpeechEngine` with `transcriptionOptions: []` on `say` speech and one real recording, and its verdict was `tts-only`: synthetic fillers mostly kept, the real recording (o1) unscripted and nearly wordless (6 words in 165 s), so its 0 tells nothing. TR-7 was held back rather than written as cloud-only, because a §11 entry is not re-litigated and the owner chose to record a scripted sample first. On that sample (o2, 29.4 s) the engine recognised 98.3 % of the script's other words and kept 1 of its 8 fillers. The spike's mechanical verdict printed `reports-real`, since any kept filler counts, but one in eight is not a source, and the owner chose "Cloud-only (Recommended)". (orig CT-0 record; TR-7)
- **The vocabulary is a choice, not a guarantee (TR-8).** AssemblyAI publishes no filler list for Universal-3.5 Pro, the app's first model. The eleven words join the Universal-2 page's nine (read through a search summary), the older page's five, and the Universal-3 Pro prompting material's er, erm, ah, hmm and mhm. Live row 22 then recorded what the real service returned: um 3, uh 2, er 1, hmm 1, every one in the list. (orig CT-1 record "TR-8's sources"; TR-8)
- **Captions read past the new key (TR-2).** A caption run takes a current marker whatever its `disfluencies` value, and an old marker decodes as false, so no project is re-transcribed on its own. Only a filler run needs `disfluencies` true. `TranscriptStamp.serves(_:for:)` is the one rule (`isCurrent`, `CloudEstimate.fate`, the keyless admission), and `MediaTranscript.captionWords(for:in:)` drops the fillers at the caption call sites (`CloudTranscriber`'s step 4, the sheet's `sampleWords()`). (orig CT-1 record; TR-1, TR-2)
- **The 32 ms grid, outward but never into a word (TR-9).** A run of consecutive fillers is widened outward to the Silero grid (`MediaSpeech.chunkTicks`), so the whole filler goes, but clamped by the neighbouring words, then snapped inward to frames as Remove Silences snaps. A candidate over another unlocked clip's word, a nest or a transition wall is dropped whole, never trimmed, so every kept edge is a grid edge. A clip on a locked track gives no candidates, because `ripple_delete_ranges` neither splits nor shifts a locked track: the filler would stay and everything else would slide. (orig CT-2 record; TR-9)
- **The sheet has no controls, and Transcribe is one media (TR-10).** TR-9 has no threshold, so there is nothing to tune; the scope is `detect_fillers`' own opening rule. The re-transcribe keeps that media's previous request (language, speakers, vocabulary) with `disfluencies` and `refresh` true, priced by `CloudEstimate.describe` of the same request and introduced by R6-2's upload sentence. Remove is disabled during a run so Return can neither cut nor cancel a paid upload mid-run. Its mirror `transcribe_for_fillers` is withheld from the assistant under AI-7, since it spends money. (orig CT-3 record; TR-10)
- **`get_transcript` never touches the network, and Stop reaches it (TR-11).** It reads the media's cached transcript when it serves `.captions`, else runs this Mac's recogniser over the clip's own window, so it uploads nothing and spends nothing and needs no AI-7 row. Because the on-device run can be long, the tool runs off main and links its `Transcriber.CancelToken` to `AgentLane.shared.callCancel`, as `transcribe` does: the assistant's Stop ends it with "The transcription was cancelled." (amends AI-16). False starts stay a judgement of meaning (TR-3): the prompt tells the assistant to cut one only when asked, say which words, then cut them in one `ripple_delete_ranges`. (orig CT-4 record; TR-5, TR-11)
- **No new op, no format change (TR-4).** A filler range is a range like a silence's, cut by the existing `ripple_delete_ranges`, so the menu and an agent make the same single undo step and nothing new is persisted. (orig "How it fits the tree"; TR-4)

## What it built — where it lives now

- Swift, new: `FillerWords.swift` (`FillerWords.assemblyAI`, `normalized`, `isFiller`, `MediaTranscript.captionWords(for:in:)`; CT-1); `FillerDetector.swift` (`read(from:clips:)`, `fillersFile`, the pure `runs`, `gridded`, `placed`, `detect`; CT-2); `AgentServer+Fillers.swift` (`detect_fillers`, CT-2; `transcribe_for_fillers`, CT-3); `FillerTranscription.swift`, `FillerSheetController.swift` and `FillerSheetController+Transcribe.swift` (CT-3); `TranscriptReader.swift` and `AgentServer+Transcript.swift` (`get_transcript`, CT-4).
- Swift, changed: `AssemblyAITranscript.swift` (`TranscriptOptions.disfluencies`, `TranscriptRequest`'s always-written key), `TranscriptStamp.swift` (`disfluencies`, `TranscriptUse`, `serves(_:for:)`), `MediaTranscript.swift`, `CloudEstimate.swift`, `CloudTranscriber.swift` and the word-captions sheet's `sampleWords()` (CT-1); `AgentCatalog+Audio.swift`, `AgentServer.swift`, `AgentCatalog.swift`, `AgentServer+Gate.swift` and `AssistantPrompt.searchTopics` (CT-2); `AppDelegate+Menus.swift`, `EditorViewController.swift`'s forward and validator line, `UIMenuTable`, `AssistantToolTable`'s withheld row (CT-3); `captionTools()`'s catalog row, `AssistantSession.cancel()`'s comment and `AssistantPrompt.swift`'s "Cutting words:" paragraph and captions topic (CT-4).
- Pure moves and visibility: `nestExtents(in:)` out of `SilenceDetector.read` into `SilenceDetector+Walls.swift`, and `MediaTranscript.project(_:in:)` made internal (CT-2); `checkSpelling(of:)` and `transcriptionLanguage(_:)` in `AgentServer+Captions.swift` made internal, bodies unchanged (CT-4).
- After the close: `AgentServer+Properties.swift`, the eight property doors moved out of `AgentServer+Clips.swift` (#333's toll); `rippleDeleteRanges`' step name (TR-12); `TranscriptReader`'s `window`, `overlapping` and `recognitionJob` (TR-13); `DeviceTranscriptCache.swift` (TR-14); `transcript_proof.py`'s P4–P8 and G6–G10.
- No Rust, header, FFI, op or format change. Tools 94 → 97 (`detect_fillers`, `transcribe_for_fillers`, `get_transcript`), app-state tools to 36.
- Proofs, probes and the spike: `tools/proof/filler_spike/` (`filler_spike_probe.swift`, `filler_spike.py`, its `README.md`; CT-0); `filler_words_probe.swift` and `filler_words_proof.py`, `assemblyai_fake.py`'s `disfluent_words`, `cloud_captions_probe.py`'s KL row, `cloud_captions_proof.py`'s rows 2, 4, FD and FL, `cloud_captions_live.py`'s row 22, `word_captions_sheet_probe.swift`'s S6 filler row (CT-1); `fillers_probe.swift` and `fillers_proof.py` (CT-2); `filler_sheet_probe.swift` and `filler_sheet_proof.py`, `inventory.json`'s site, `assistant_lane_probe.swift`'s fifth L4 case (CT-3); `transcript_probe.swift` and `transcript_proof.py`, `recording_probe.py`'s 7b (CT-4); the tool counts in `op_argument_proof.py` (97), `phase9_proof.py`, `recording_probe.py`, `recording_proof.py` and `assistant_session_proof.py`; `tools/proof/README.md`'s "Cut by transcript CT-0…CT-4" sections. The screen `designs/screens/14b-remove-filler-words-sheet.md` (CT-3).
- Person checks, in `docs/manual-checks.md`: FIL-1 (CT-3, a real recording's filler cut), AS-10 (CT-4, false starts with a real key), and Clip ▸ Remove Filler Words… added to CH-4's list (CT-3).

**Headline numbers** (macOS 26.5.1; every app proof under `env -u RC_ASSEMBLYAI_KEY` except CT-1's live run).

The filler spike (on-device, en-US, `transcriptionOptions: []`; CT-0 and TR-7):

| Row | Audio | Words recognised | Fillers kept |
|---|---|---|---|
| f1 | `say`, the script as written, 13.066 s | 27 | 6 of 8 (um 3, uh 3; "er" came back "or", "hmm" dropped) |
| f2 | `say`, silence around each filler, 15.429 s | 27 | 7 of 8 (um 3, uh 2, er 1, hmm 1) |
| f3 | `say`, the script without fillers (the control), 8.117 s | 20 | 0 (script 100 %) |
| o1 | the owner's `owner-sync/record.aifc`, 165.002 s | 6 | 0 (unscripted; mean level −46.1 dB) |
| o2 | the owner reading `O2_SCRIPT`, 29.4 s | 59 | 1 of 8 (the first "um"; 98.3 % of the other words) |

| Measure | Measured | Command |
|---|---|---|
| The real service's fillers (CT-1) | live row 22 on `fillers.aiff`: um 3, uh 2, er 1, hmm 1, every one in TR-8's list; one scripted "uh" not returned; none reached a cue | `RC_PROOF_APP=release cloud_captions_proof.py --live` (44/44) |
| A known filler cut (CT-2, #92's done-when) | M1 [[1460000, 1780000]] with words "um,", "Uh", "er"; M2 clips [0, 1460000) in 0 and 1460000 in 1780000, one undo back to one clip | `RC_PROOF_APP=release fillers_proof.py` (17/17) |
| The sheet (CT-3) | T5 "1 cut · removes 00:00:00:16", the wash on the timeline only while the sheet is up | `RC_PROOF_APP=release filler_sheet_proof.py` (15/15) |
| `get_transcript` (CT-4) | G1 the eight mapped words with "um,", "Uh", "er" flagged and no AssemblyAI request; G5 17 on-device words; A1 clips (0, 360000, 0) and (360000, 2040000, 960000), one undo back to (0, 3000000, 0); A3 stopped at 2012 ms, answered at 2127 ms with "The transcription was cancelled." | `RC_PROOF_APP=release transcript_proof.py` (13/13) |
| The prompt (CT-4) | system 3134 of 6000, guide 1486 of 1500 | `assistant_prompt_proof.py --probe` F6 |
| Spend | AssemblyAI $0.0016 (CT-1's live run only, 27 billed seconds); Anthropic $0 | the live ledger `work/cloudlive/ledger.json` |

Mutants, each run once on the final instrument and each caught: CT-0 three (the spike's `--mutant`), CT-1 nine (`filler_words_proof.py` eight, `cloud_captions_probe.py`'s `keyless-strict-marker`), CT-2 eight (`fillers_proof.py`), CT-3 nine (`filler_sheet_proof.py`), CT-4 six (`transcript_proof.py`); TR-7 and CT-5 none.

## Known limits

- **Cloud-only** (TR-7): a person with no AssemblyAI key has no filler removal; the sheet says so.
- **TR-8's list:** a filler the service returns outside it is captioned, and a real "ah", "er" or the letter "M" is dropped from captions.
- **The service misses fillers:** one scripted "uh" of eight was not returned on live row 22.
- **TR-9's edges:** an inward frame snap can leave up to a frame of a filler, and speech on an unlocked track whose media has no transcript is not protected.
- **TR-2's second paid transcription:** a project transcribed before CT-1 is transcribed again before its fillers can be cut.
- **A pre-CT-1 cache file's janitor rewrite** writes `"disfluencies":false` into its `requested` when a delete was owed: the old request's true value, read the same as an absent key, `words` untouched (orig CT-1 record). Harmless.
- **The assistant's guide** stands at 1486 of its 1500 characters.
- **`get_transcript`'s on-device window** (TR-13): the recogniser hears less context, so a windowed answer can differ from the whole clip's.
- **The on-device cache** (TR-14): a windowed miss recognises and stores its own span only, and a later call outside every stored run recognises again; no gap-filling, no merging across runs.
- **An agent's silence cut** reads "Undo Ripple Delete", not the sheet's "Undo Remove Silences" (TR-12).

## Open items

None still open. Filed at CT-5 and closed by the residue batch (2026-10-23): #333 (TR-12), #331 (TR-13) and #332 (TR-14).

#92 is closed by the orchestrator after this record's merge.

Not filed, each decided at the close:
- An on-device filler source: TR-7 is the owner's decision; `tools/proof/filler_spike/` re-runs the measurement, and a later engine that keeps fillers would be a new decision.
- `cloud_captions_live.py` computing `billed` twice (l.399–400): a nit the CT-1 review left; the output is right, and it is a paid instrument that cannot be re-run free.
- o1's 6 words in 165 s: its mean level is −46.1 dB, so no defect is established.
- CT-3's internal-`var` deviations (`mediaRows`, the run's `cloud`, `token`, `lastError`, `runnable`, `tornDown`): accepted at review.

## Where to look in the original

- "Goal": #92's ask, the two paths and the done-when.
- "The owner's choices": the owner's comment of 2026-09-30 verbatim and the ask of 2026-10-22.
- "How it fits the tree": every piece the phases built on at `15d3545` — the words' mapping, the cloud request, the caption producers, Remove Silences, the cut, the assistant, the on-device engine.
- "Phases": what each of CT-0…CT-5 was to build.
- "Person checks": FIL-1 and AS-10.
- CT-0: the spike's run, its table and the o1 format, what the answer means, why TR-7 was held back, the owner's sample and TR-7.
- CT-1: the landed list, TR-8's sources, the runs, the nine mutants, live row 22 and the spend, the janitor note, the review's nits.
- CT-2: the landed list, the runs, the eight mutants, the `fillersFile` deviation.
- CT-3: the landed list, the runs, the nine mutants, the internal-`var` deviations and the undo name left alone.
- CT-4: the landed list, the runs, the six mutants (`no-transcript-stop`'s 49,052 ms), the 7b deviation, the residue named for CT-5.
- CT-5: the close, the issues filed and not filed.
