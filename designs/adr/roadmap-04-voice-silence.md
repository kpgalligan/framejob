# Remove Silences judged by voice (road map 4)

- **Status:** Built (S1 `1c3e92e`, 2026-09-15; proved 2026-09-19; reader review and residue closed
  2026-09-20; its #23 follow-up closed 2026-09-22). Only the person-at-the-machine checks are left.
- **Original:** `archive/reelcut-roadmap-4.md` (1378 lines). This file cites its sections as "orig §x".
- **Spec decisions:** spec §11 has five unnumbered bullets for road map 4's S0/S1, starting "The
  silence detector's second signal is a voice-activity model". In short: Silero VAD v6.2.1 runs
  through Core ML. Edges come from its 32 ms grid, and level judges only where no voice is found,
  per clip window. The probabilities are a per-media cache. Voice is the default mode. No network
  model is used. **S1-23** (a peaks marker certifies a complete decode) came from #23 (orig §9). It
  also relies on #22's decision that a media clip's length snaps down, and on D4-3 (`set_speed`
  holds the window).

## Context

Road map 2 phase 3a shipped Clip ▸ Remove Silences… and `detect_silence` with one rule: a moment
is quiet when `peak × envelope` is below a fixed −40 dBFS. The spike measured two ways this rule is
wrong in kind, and no better number fixes either (orig §1):

- A quiet microphone puts the voice under the threshold. The rule marked 18.9 s of the app's own
  21 s recording silent.
- A hum puts the silence over the threshold. Under a −32 dBFS hum the rule found 0 runs at every
  threshold.

The −40 default was picked on a `say` fixture that had digital silence between sentences, so that
fixture could not show either failure (orig §6). The fix adds a second signal that says whether a
voice is present.

## Decisions

- **Silent means "nobody is talking", judged by Silero VAD v6.2.1 run as a Core ML program**
  (orig §0, §3.1; spec §11). The model is the third-party conversion
  `aufklarer/Silero-VAD-v6.2.1-CoreML`, MIT like the upstream, in FP16 and 640 KB. It is vendored
  compiled with its LICENSE and a PROVENANCE file (tag, repo, revision, sha256 per file). The
  PROVENANCE file keeps re-converting from upstream with coremltools as an option. Core ML is the
  only runtime, so there is no new dependency, TCC grant or `async` exception. It is the app's
  first ML asset.
- **The streaming variant uses a 32 ms step.** Each prediction takes 512 new samples at 16 kHz plus
  64 samples of carried left context. The LSTM `h`/`c` state is fed back each step, and the
  remainder is held across `feed` calls. `MLModel.prediction` is synchronous, so one class serves
  the cache pass (orig §2 q6, §4b).
- **Compute units are `.cpuAndNeuralEngine`.** The spike measured `.cpuOnly` giving byte-identical
  decisions and traces identical to two decimals, which is why a proof can pin a trace (orig q6).
- **Edges come from the model's own grid, inward. There is no adaptive threshold, no hysteresis
  and no level-based edge refinement** (orig §3.2, §7).
  - The measured edge error is inside the 0.1 s padding the feature already keeps. Starts land
    60–100 ms late (offset lag, inward) and ends land within one chunk.
  - Hysteresis (onset 0.5, offset 0.35) moved no edge by more than a chunk, so the feature exposes
    one number.
  - Refining edges by level is to be revisited only if the listening check says padding should be
    zero.
- **The probabilities are a per-media cache and are never computed when the feature runs**
  (orig §3.3, §4a; spec §5.6).
  - The cache is `cache/speech/<id>.bin`: one f32 per 32 ms chunk of source time
    (`MediaSpeech.chunkTicks` = 19 200 ticks), `ceil(duration/chunk)` entries from t = 0.
  - Its marker is `<id>.complete.json`, holding a `SpeechStamp`. The stamp wraps `CacheStamp` and
    adds `speechModel` and `speechChunkSamples`, so a model change rebuilds speech caches and
    nothing else.
  - The pass runs **after** `peaks` in `generateCaches`, in the same `CacheLedger` slot. Running it
    first would hold the peaks withdrawal behind a full-file decode and inference.
- **The cache is written only when the reader completed** (orig §8 R2·1).
  - A nil sample buffer can mean the end of the track or a failed decode. The zero-filled buffer
    reads as "nobody talking", so a certified partial decode would cut the undecodable tail. This
    was measured: 8.1 s proposed out of a 10.4 s file.
  - `reader.status` is read before the cancel. Anything other than `.completed` writes no `.bin`,
    no marker and no post, and the media stays `voice_pending`.
  - #23 applied the same fix to peaks (orig §9, S1-23).
- **The withdrawal post carries `replaced: true`, and the arrival post does not** (orig §8). A
  withdrawal opens a pass that replaces a file already on disk.
- **When the model is unavailable, the app falls back and does not crash** (orig §4a, §4c). The
  model can fail to load because the bundle lacks the folder (the offscreen harness is one such
  bundle) or because Core ML fails. In that case:
  - `SileroVAD` keeps one process-wide, `NSLock`-guarded reason and never retries until relaunch.
  - The sheet opens on Level with its Voice row disabled.
  - The tool refuses `mode: "voice"` with a sentence.
- **Voice is the default mode. Level stays as a mode and as the fallback, and its arithmetic is
  unchanged** (orig §3.4). A project whose sound is tones detects exactly what it did before: phase
  3's proofs scored the same.
- **Each step's test runs in a fixed order** (orig §8):
  1. The gain floor (the plan's envelope alone): a turned-down, faded or ducked clip is quiet in
     either mode.
  2. If the clip's window holds no voice, the level test.
  3. If the speech cache is missing, never quiet by the model, and not judged by level either.
  4. Otherwise, the voice test: quiet when the max probability over the chunks the step touches is
     below `voiceConfidence`. The detector takes the max, as the level test takes the peak, because
     that is conservative for a destructive edit. The mean was measured moving edges outward.
- **The fallback is decided per voice (clip segment) over its own source window, not per media or
  whole file** (orig §4c, §8, the defect fixed 2026-09-19; spec §11). A file that is speech then
  music is judged by the model over one clip and by level over the other. `judgedByLevel` still
  names **media**, because the notes name files a person can see. Its sentences say "in at least
  one clip".
- **`voiceConfidence` defaults to 0.5, clamped to 0.1…0.9**, the range the model's authors say to
  tune inside. It is refused by name with `mode: "level"`: the app refuses a value it cannot use
  rather than dropping it (orig §4c, §4e).
- **`detect_silence` reads `min_length` and `padding` as given, not frame-snapped, which mirrors
  the sheet** (orig §8 R1·1). Only span bounds land on the frame grid, via `refine`'s directional
  snap: a start snaps up, an end snaps down.
- **Both durations are bounded by `AgentServer.durationCeiling` and published as the schema's
  `minimum`/`maximum`** (orig §8, sceptic finding 1). Before the bound, an Int64.max padding
  overflowed in `refine` and killed the app. The sheet cannot reach that value because it clamps
  its fields.
- **The pending notes promise only what the answer shows** (orig §8 R3·1, sceptic finding 2,
  residue).
  - `Outcome.proposedMedia` names the media that some proposed span lands inside. A note says
    "nothing is proposed" only for a waiter outside that set, because the gain floor can propose
    inside a media that has no cache.
  - The sheet's waveform line uses `waveformPromise()`, which hedges. It does not use
    `promise(about:)`: in the `afterPeaksGone` state that helper would answer "quiet in the MIX",
    which is false there (mutant (e)).
- **No op, schema, FFI or tool changes, and the core is untouched** (orig §4). `detect_silence`
  gained `mode`, `voice_confidence` and the result keys `mode`, `voice_confidence`,
  `judged_by_level` and `voice_pending`. The two waiters fold into `pending_peaks`. The sheet gained
  a "Judge by:" popup.
- **Nothing in the sheet is persisted, including its mode** (orig §7), which matches the sheet's
  existing posture.
- **Gemini and other network models are excluded from the silence path** (orig §2 q8, §3.5).
  Gemini's timestamps have 1 s resolution and drift, its audio would leave the machine, and nothing
  about it can be proved byte for byte. A transcript-level edit is where such a model would belong.
- **Two size tolls were paid first, each as a pure move** (orig §4c, §4e, §8):
  - `SilenceDetector+Walls.swift` (the nest walls and the frame snap, and later `refine`).
  - `AgentCatalog+Audio.swift` (`detect_silence`, `normalize_clip`), spliced back into the catalog
    at the same position so `tools/list` keeps its order.

## What it built — where it lives now

- `app/Sources/SileroVAD.swift`: the streaming wrapper, availability, and `bundled()`.
- `app/Sources/MediaSpeech.swift`: the chunk grid, the `Loader` and `speechMax`.
- `app/Sources/MediaPeaks.swift`: holds the window arithmetic that peaks and speech share. The
  reversed mirror is in `app/Sources/ReverseMirror.swift` since road map 7.
- `app/Sources/MediaImporter+Speech.swift`: `speechIsCurrent` and `writeSpeech`. The call site is
  in `MediaImporter.swift`.
- `app/Sources/MediaCacheFiles.swift`: `SpeechStamp`, the URLs and `speechKind`.
- `app/Sources/SilenceDetector.swift`: `Mode`, the voice test, the per-voice fallback and
  `Outcome`. It is at 586 of the 600 cap.
- `app/Sources/SilenceDetector+Walls.swift`: the walls, the snap and `refine`.
- `app/Sources/SilenceSheetController.swift`: the Judge-by popup, the notes and `cacheChanged`.
- `app/Sources/AgentServer+Silence.swift`: the handler.
- `app/Sources/AgentCatalog+Audio.swift`: the catalog entry.
- `app/Resources/Models/silero_vad.mlmodelc`, `LICENSE`, `PROVENANCE.md`: the model.
- `tools/proof/silence2_proof.py` (MCP, 91 rows), `silence2_probe.py` (probe, 76 rows) and
  `silence2_trace.json` (a 325-chunk pin keyed on the sha256 of the decoded samples) prove the
  feature. The spike's instruments are in `tools/proof/silence_spike/`.
- #23's peaks work is in `app/Sources/MediaImporter+Peaks.swift` and
  `app/Sources/MediaPeakBuckets.swift`. `tools/proof/peaks_probe.py` and `peaks_proof.py` prove it.

## Known limits

Still true of the current code:

- **A reversed clip reads the forward file's probabilities, mirrored.** Presence of a voice is
  near enough symmetric for a cut, but chunk boundaries are not, so a reversed edge can be off by a
  chunk (orig §5).
- **The model's known weak material was not measured.** That material is voice-like instruments,
  singing and very high-pitched voices (orig §5).
- **A soft opening word at low SNR can read as no voice and be cut into.** `quiet2.wav` lost "The".
  The 0.1 s padding is the only guard (orig §5, q6).
- **The fallback test is one scalar per window.** A clip with one second of speech in twenty
  minutes of music is judged by voice for its whole length. The scope popup is the way out
  (orig §5).
- **A hard-panned voice is halved before the model sees it.** The model reads 16 kHz mono of
  AVFoundation's downmix (orig §5).
- **`speechIsCurrent` checks that the `.bin` exists, not that it has the right length.** Past the
  end of a short file, a moment reads quiet. Only a hand edit of the cache can make a short file,
  so this is a limit and not a defect (orig §5, R2·3).
- **A padding finer than a frame is honoured only to within one frame**, because span bounds are
  frame-snapped (orig §5).
- **The cache pass's `.bin` is not bit-identical to `probabilities(of:)` over the same file.** 30–70
  of 325 chunks differ by at most 0.0022, because `alwaysCopiesSampleData = false` changes the
  converter's block sizes. Every decision at 0.5 is the same (orig §8).
- **The notes are media-granular.** They cannot name which clip the mix made quiet, so the sheet
  hedges instead. A per-voice `Outcome` field would need a size toll, because `SilenceDetector` is
  at 586 (orig §8 residue).
- **Under a nest, `detect_silence`'s `clips` reports the inner clip's id.** The plan flattens nests.
  The behaviour is consistent and is accepted back as a scope (orig §8, reader 3, not re-measured).
- **A peaks edge shortfall of a full 10 ms bucket or more is never certified.** The waveform stays
  pending instead. A source change that keeps both file size and modification second is not
  detected (orig §9).
- **The one real mixed recording in hand defeats both VADs** (orig q7). Silero heard under 0.6 s of
  speech in it, and nobody has listened to the file. This is why the check by ear is owed.

Measured and rejected, so no one re-tries them blind (orig §2, §7):

- **Adaptive threshold** (floor p10 + 12 dB, the field's "Auto"): it fixes the quiet mic but is
  destructive under a hum, cutting 9.5 s of a 10.4 s fixture at −20 dBFS.
- **Apple `SpeechDetector`**: run alone, it traps ("use with a transcriber module"). Paired with a
  transcriber, it returned zero results at every sensitivity on four inputs. It is also
  `async`-only.
- **`SpeechTranscriber` word gaps**: a word's range absorbs the pause before it, by up to 1.4 s. It
  found 0 of 2 pauses.
- **SoundAnalysis `SNClassifySoundRequest`**: its edges land 0.22–0.30 s outward into the words.
  Its window is 0.5–15 s, and it is 15× slower than Silero. It heard no speech in the real mixed
  file at a 1 s window.
- **Mean instead of max over a step**: edges move outward (a scored mutant).
- **TEN VAD**: its licence has a non-compete clause and "solely for your Application(s)", and it
  has no Core ML port. It needs a legal read and was not measured.
- **libfvad**: a binary decision every 10 ms, at 50 % TPR at 5 % FPR in noise.
- **Any Rust route**: that would be sample work in Rust, which spec §7 forbids.
- **The whisper.cpp ggml port**: heavier than a single `.mlmodelc`.
- **Gemini**: see Decisions.
- **Silero's own figures**: it runs at 332–393× realtime, about 7 s for a forty-minute file. Every
  fixture held at a threshold of 0.5.

When the original was written, the deployment target was macOS 15. The minimum is now macOS 26
(spec §11 W-8). The spike's finding that `SpeechTranscriber` needs no speech grant was acted on
there (orig §6).

## Open items

- Three listening checks need a person at the machine: a narrated screencast recorded by the app,
  with the truth marked by ear; a cut heard across a voice-mode boundary, and whether padding should
  drop to 0.05 s (which would reopen level-based edge refinement); and the sheet's note with one
  file pending and another judged by level. These are tracked in `designs/reelcut-remaining.md`
  §4g.
- #23's person check needs a person at the machine: a human listen, and a visual waveform judgement
  on real footage. Tracked in `designs/reelcut-remaining.md` §4a.
- Unscored proof branch: the tool note's mixed ending, "spans inside N of them ARE proposed here
  and nothing inside the other M is". A row needs a document with two waveform-waiting media, one of
  them ducked. Tracked in `designs/reelcut-remaining.md` §5b.
- README drift: `README.md`'s catalog file-map row omits `AgentCatalog+Audio`, `+Transitions`,
  `+Declarations` and `+Graphics`. Tracked in `designs/reelcut-remaining.md` §5c.
- A per-voice `Outcome`, so the notes name a clip (optional; `SilenceDetector.swift` pays a toll
  first). Tracked in `designs/reelcut-remaining.md` §5d ("Smaller") and §3.
- Candidate: a transcript-level edit ("remove the ums and false starts"), which is where a network
  model would belong. Tracked in `designs/reelcut-remaining.md` §5d ("Captions").

## Where to look in the original

- orig §0–§1: the decision in one paragraph, and the shipped rule's measured failures.
- orig §2: spike S0, questions q1–q8. The adaptive threshold, `SpeechDetector`, word gaps,
  SoundAnalysis, the Silero table of edge errors, the real mixed file, and Gemini with the library
  field.
- orig §3: the five decisions that became spec §11.
- orig §4a–§4h: the plan (cache format, wrapper, detector rule, sheet, MCP mirror, file table,
  proof claims 1–17 with their planned mutants, person checks).
- orig §5–§7: the limits recorded, findings about older ground (the grant, the −40 default, the
  ffmpeg `sine` level), and what was not built and why.
- orig §8: the S1 record. The mutant table, the four deviations from §4g, the two defects fixed on
  2026-09-19, the reader review (R1·1–R4·4 with the W1/W2 builds), the sceptic's pass, and the
  closed residue (with the `waveformPromise` versus `promise(about:)` decision).
- orig §9: #23. The peaks marker certifies a complete decode, including the coverage-boundary
  arithmetic and its mutants.
