# Reelcut — road map 4: Remove Silences, second pass

**Status: BUILT — S1 landed in `1c3e92e` (2026-09-15); its own proof
instruments (§4g) are still owed.** The spike (S0) was RUN on 2026-09-13 and
its answers are pasted below before any plan leans on them; §8 is the record
of what landed, what was verified and what is owed. The sections between
are the plan as it was written.

Road map 2's phase 3a shipped Clip ▸ Remove Silences… and `detect_silence`
over one rule: a moment is quiet when `peak × envelope` is under a fixed
threshold, −40 dBFS by default (`app/Sources/SilenceDetector.swift`). That
is what every shipping silence remover does — the research below found
DaVinci Resolve 20.2, TimeBolt, Recut and AutoCut all documenting a level
threshold plus padding plus a minimum — and it is wrong for the recordings
this app now makes itself, in two ways a spike measured rather than argued:
a quiet microphone puts the VOICE under the threshold, and a hum puts the
SILENCE over it. Neither is fixable with a better number. The answer is a
second signal that says whether a moment holds a voice, and the spike found
one that ships as a 640 KB file, needs no new runtime, no grant, no `async`
and no change to the deployment target, and lands its edges within a frame.

---

## 0. The decision, in one paragraph

**"Silent" will mean "nobody is talking", judged by a voice-activity model
(Silero VAD v6.2.1 run through Core ML), cached per media beside the peaks,
with the shipped level rule kept as the judge for media that hold no speech
at all.** The model's probabilities go into `cache/speech/<media id>.bin`
under the same stamp-and-marker discipline as `peaks/`, written by a third
pass in `MediaImporter.generateCaches`; `SilenceDetector` gains a `mode`
— `voice` (the new default) or `level` (today's rule, unchanged) — and in
voice mode a moment is dead where no clip in scope holds a voice, while a
clip whose media never holds one is judged by level so a music bed or a
tone keeps protecting the way it does today. No op, no schema change, no
FFI change, no new tool: `detect_silence` gains two arguments and the sheet
gains one popup. Gemini is not part of it and this document says why in §2.

---

## 1. What is wrong with what shipped — measured

Two of the recorder's own files from road map 3's smoke runs (in
`~/Movies/Reelcut Recordings/`, host inputs named by path and not tracked)
and six synthesised fixtures went through the shipped rule's arithmetic
re-implemented outside the app (10 ms peak buckets of a 16 kHz mono
extract; `tools/proof/silence_spike/level_apple.swift`):

| Input | Floor (p10 of peak buckets) | Speech peaks (p99) | The shipped −40 dBFS rule says |
|---|---|---|---|
| The 21 s microphone file of 2026-09-11 20:11 | −61.8 dBFS | −15.3 dBFS | **18.9 s of 21.1 s is silent** (3 runs) — the voice sits under −40 most of the time |
| `say` fixture at −35 dB over pink noise at a −70 floor (`quiet2.wav`) | −70.2 | −36.9 | **6 runs, 5.97 s**, where the two real pauses total 2.74 s — the rule eats into words |
| `say` fixture under a hum with a −32 dBFS floor (`hum3.wav`) | −32.1 | −19.9 | **0 runs** at −40, −50 and −60 — the hum is over the threshold everywhere |
| The 26 s display recording of 20:13 (microphone folded into system audio) | −45.3 | −13.9 | 1.85 s in 2 runs, where the transcriber hears two phrases and a hum |

The first row is the one that matters: it is a file this app recorded, and
the default proposes to delete nine tenths of it. The default is not
wrong by a few dB; it is wrong in KIND, because a level says nothing about
whether the level is a voice. An adaptive threshold (the file's own floor
plus a margin — Recut and AutoCut both ship an "Auto") was measured too and
is recorded in §7: it fixes the quiet microphone and is DESTRUCTIVE under
the hum (floor −32 + 12 = −20 dBFS cut 9.5 s of the 10.4 s fixture), so it
solves one of the two failures by making the other worse.

---

## 2. S0 — the spike, run on 2026-09-13 before the plan

Host: macOS 26.5.1, Xcode 26.2, Apple Silicon; the app's deployment target
is macOS 15.0 (`project.yml`). The instruments are three Swift programs in
`tools/proof/silence_spike/` (the README there has every build, run and
fixture line), compiled with `swiftc` against the SDK and run from a shell,
so everything here ran under the terminal's TCC attribution, as every
proof does. Eight inputs: the two recorder files above, `say -o` with two
`[[slnc]]` pauses (10.39 s; the level rule on its digital silence puts the
pauses at **2.72–4.29 and 6.68–7.81**, which is the ground truth every edge
below is measured against; −50 dBFS moves those bounds by ≤ 0.04 s), and
five ffmpeg mixes of that fixture: attenuated 30 dB (`quiet.wav`), −35 dB
over pink noise (`quiet2.wav`), and under a 120 Hz hum at three levels
(`hum.wav` −66 dBFS, `hum2.wav` −51, `hum3.wav` −32 — this ffmpeg's `sine`
sits at −21 dBFS, as `tools/proof/README.md` already records, so a
`volume` of −14 dB is a −35 dBFS hum).

**q1. Does the shipped default hold on a real recording?** No — §1.

**q2. Does an adaptive threshold fix it?** Half. Threshold = p10 of the
peak buckets + 12 dB: on the microphone file −49.8 dBFS, ten runs and the
same spans as −50; on `quiet2.wav` −58.2, the two pauses exactly; on the
clean fixture the floor is digital silence (−120) so it must be clamped;
on `hum3.wav` −20.1 dBFS and 9.51 s cut. A margin over the floor cannot
tell a hum from a room, which is the whole problem. Not built (§7).

**q3. Apple's `SpeechDetector` (macOS 26 Speech framework).** Compiles
(`SpeechDetector(detectionOptions: .init(sensitivityLevel:), reportResults:
true)`, `results` yielding `speechDetected` and a `CMTimeRange`). Run
alone it TRAPS: `Speech/SpeechDetector.swift:223: Fatal error: Cannot
create SpeechDetector-only worker; use with a transcriber module` — Apple's
own page says "This module only functions in conjunction with a
`SpeechTranscriber` or `DictationTranscriber` module". Paired with a
`SpeechTranscriber` it reported **zero results** at all three sensitivity
levels on four inputs, in file mode (`analyzeSequence(from: AVAudioFile)`)
and in streaming mode (an `AsyncStream<AnalyzerInput>` of converted
buffers), while the transcriber beside it produced 3–45 results. Apple's
page again: results "currently only support error handling from the VAD
model". It is also `async`-only (an actor with an `AsyncSequence`), the
exception spec §11 already declined. **Out.**

**q4. The transcriber's word ranges as the gaps.** `SpeechTranscriber`
with `attributeOptions: [.audioTimeRange]` ran headless, 20–130× realtime,
and — worth recording on its own — with **no speech-recognition grant**:
`SFSpeechRecognizer.authorizationStatus()` was `notDetermined` before and
after, and words came back. But a word's range ABSORBS the pause before
it: on the clean fixture "Pack" is timed 3.18–4.56 where sound resumes at
4.29, and "How" 6.90–8.04 where it resumes at 7.81 — up to 1.4 s of
silence attributed to the next word — so the gap between words found
**0 of the 2 pauses** at ≥ 0.5 s. A lower bound on a gap, never an edge.
**Out** as a detector; the grant fact goes to §6.

**q5. SoundAnalysis' built-in classifier (`SNClassifySoundRequest`,
`.version1`).** 303 labels, `speech` among them; window constraint
0.5–15 s; a `SNAudioFileAnalyzer` over the extract with no grant and a
callback API; 22–26× realtime at 90 % overlap. At a 0.5 s window it
separates badly (room tone on the microphone file reads 0.34 median, 0.40
p90 for `speech`; the "ba ba ba" 0.41 median) and at 1.0 s well (room tone
p90 0.03). It found both fixture pauses under every hum and attenuation —
but its edges land **0.22–0.30 s OUTWARD into the neighbouring words**
(`hum3.wav`: 2.50–4.55 and 6.45–8.05 at 0.5 s; 2.40–4.60 and 6.40–7.90 at
1.0 s), because a window that is 44 % speech reads as not speech, and a
cut on those bounds clips the tail of "dog." and the attack of "Pack". On
the display recording it heard speech in 0.35 s at a 0.5 s window and
none at 1.0 s. A general sound classifier, not a VAD. **Out** (§7 records
its one merit).

**q6. Silero VAD v6.2.1 through Core ML.** The third-party conversion
`aufklarer/Silero-VAD-v6.2.1-CoreML` (Hugging Face; MIT, as the upstream
`snakers4/silero-vad` is; converted from tag v6.2.1 with coremltools 8.3,
FP16, Core ML specification version 8 — macOS 14 and up, under the app's
15.0 target). The 32 ms streaming variant is a 640 KB `.mlmodelc`: input
`audio` `[1,1,576]` (64 samples of left context + 512 new samples at
16 kHz), LSTM state `h` and `c` `[1,1,128]` in and `h_out`/`c_out` back,
`probability` `[1]`. Driven from Swift over `MLModel.prediction(from:)`
— synchronous — with the state fed back and the context carried
(`tools/proof/silence_spike/silero_coreml.swift`):

| Input | Non-speech spans ≥ 0.5 s at probability < 0.5 | Edge error vs the truth (start, end) |
|---|---|---|
| clean fixture | 2.78–4.29, 6.75–7.84 | +0.06 −0.00, +0.07 +0.03 |
| `quiet.wav` (−30 dB) | 2.78–4.29, 6.75–7.84 | +0.06 −0.00, +0.07 +0.03 |
| `quiet2.wav` (−35 dB over pink) | 2.75–4.32, 6.75–7.87, and 0.00–0.54 | +0.03 +0.03, +0.07 +0.06; the soft first word "The" missed at that SNR |
| `hum.wav` (−66 dBFS hum) | 2.78–4.29, 6.75–7.84 | as clean |
| `hum2.wav` (−51) | 2.82–4.32, 6.75–7.84 | +0.10 +0.03, +0.07 +0.03 |
| **`hum3.wav` (−32, the shipped rule blind)** | **2.82–4.29, 6.75–7.84** | +0.10 −0.00, +0.07 +0.03 |
| microphone file | speech at 18.37–19.39 only | the transcriber's "ba" ×6 sit at 17.79–19.71 — its absorbed lead-in again |

Every start lands 60–100 ms LATE (the model keeps calling speech for two
or three chunks after a word ends — the "offset lag" the field reports of
Silero, small here) and every end lands within one chunk of the next
word's onset. Both errors are INWARD: the dead span the model reports is
shorter than the true silence, which is the conservative direction for a
cut, and the late start keeps about as much room tone after a word as the
shipped rule's 0.1 s padding keeps on purpose. Speed **332–393×
realtime** on `.cpuAndNeuralEngine`, 0.01–0.06 s to load; a forty-minute
recording is about seven seconds. Hysteresis (onset 0.5, offset 0.35,
Silero's own post-processing) moved no edge by more than one chunk on any
fixture, so one threshold is enough. **`.cpuOnly` gives byte-identical
decisions and two-decimal-identical traces** on the clean fixture and
`hum3.wav`, which is what lets a proof pin a trace. Its documented
weaknesses (voice-like instruments, singing, very high-pitched voices)
are not this app's material; its threshold is meant to be tuned per domain
and 0.5 held on every fixture here.

**q7. The one real mixed recording defeats both VADs.** The 20:13 display
recording (an R1-era file with the microphone folded into the system
track — R0's finding) carries a hum the transcriber renders as "Mm hmm"
and two phrases it renders as "Oh, there it is" (17.86–19.18) and "Put it
in there" (22.06–22.60). Silero calls speech in four blips totalling under
0.6 s; SoundAnalysis in 0.35 s. What the file actually holds is unknown —
nobody listened to it — so this is not a verdict on either model; it is
the reason S1's proof must record its OWN real material at the machine
and mark the truth by ear (§4h), the host-state lesson of road map 3.

**q8. Gemini, and the library field** (a research pass with URLs, folded
here). Gemini's audio API references time in `MM:SS`, the documented
resolution is a second, and users report progressive drift of 1.35 to
13.2 s per minute on the 3-series models; the one project pairing Gemini
with silence removal does so with Silero because Gemini "cannot provide
the frame-level accurate timestamps". At 1,920 tokens a minute it is cheap
($0.0006–0.0024/min) and it is still the wrong tool: a screencast's audio
would leave the machine, a cut needs 10–30 ms, and nothing about a
network answer can be proved byte for byte. Where a model of that kind
WOULD earn its place is a transcript-level edit ("remove the ums and the
false starts"), which phase 4's captions already have the words for and
which is a different road-map item. The libraries, ranked for a Swift app
that wants no new runtime first and accuracy second:

| Candidate | License | Runtime it needs | Hop | Measured or reported | Verdict |
|---|---|---|---|---|---|
| **Silero VAD v6.2.1, Core ML** | MIT (model and conversion) | Core ML, in the OS | 32 ms | q6, measured here | **Chosen** |
| Silero via whisper.cpp's ggml port | MIT | ggml vendored as C (885 KB model) | 32 ms | same model | Heavier than one `.mlmodelc` |
| Silero via Rust (`silero-vad-pure`, `voice_activity_detector`, `silero-vad-rs`) | MIT | none / onnxruntime / tract | 32 ms | same model | Sample work in Rust, which spec §7 forbids |
| TEN VAD | Apache 2.0 **plus a non-compete and "solely for your Application(s)" clause** | prebuilt dylib or onnxruntime; no Core ML port | 10 / 16 ms | vendor PR curves, no F1 | Needs a legal read; not measured |
| libfvad (WebRTC GMM) | BSD-3 | none, C | 10/20/30 ms, binary | 50 % TPR at 5 % FPR in noise (Picovoice) | A modest step over a threshold |
| FSMN-VAD, RNNoise's VAD output, pyannote, Cobra | Apache / BSD / MIT-gated / commercial | onnxruntime / C / PyTorch / a phoning-home key | 10 ms | — | Not pursued |
| Apple `SpeechDetector` | system | none | undocumented | q3: zero results | Out |
| Apple SoundAnalysis | system | none | ≥ 0.5 s window | q5: edges 0.25 s outward | Out |
| Apple `SFSpeechRecognizer` word times | system | none | word | q4's shape, plus a grant and a one-minute ceiling | Out |
| Gemini | API | network | 1 s, drifting | reported | Out |

---

## 3. Decisions for spec §11

1. **The silence detector's second signal is a voice-activity model, and
   the model is Silero VAD v6.2.1 as a Core ML program.** It is the app's
   first ML asset. It is vendored COMPILED (`silero_vad.mlmodelc`, 640 KB,
   FP16) with its MIT notice and a provenance file naming the upstream tag,
   the conversion's repository and the download's ETag, so a re-conversion
   from the MIT upstream with coremltools is a documented option and not
   the only route. Core ML is the runtime; nothing else is added.
2. **Edges come from the model's own 32 ms grid, inward; the level rule
   is the judge only for media that hold no voice.** No adaptive threshold
   (q2), no level-based edge refinement (§7): the measured edge error is
   inside the padding the feature already keeps.
3. **The probabilities are a per-media CACHE, never computed at feature
   time.** `cache/speech/<media id>.bin` beside `peaks/`, stamped and
   marked on the same terms (spec §5.6), written by `MediaImporter`'s
   pass — so the model runs where `await` is already allowed and
   `MLModel.prediction` is synchronous anyway. **No new `async`
   exception, no `@available`, no deployment-target change.**
4. **Voice is the default mode** for the sheet and for `detect_silence`;
   level stays as a mode and as the fallback, unchanged in its arithmetic,
   so a project whose sound is tones (road map 2's phase-3 fixtures are)
   detects exactly what it did.
5. **No network model in the silence path.** Gemini and its kind are
   excluded for this feature by q8; a transcript-level edit is where such
   a model would go, and that is a separate item on a later list.

---

## 4. S1 — the phase

No op (`OP_NAMES` stays 55), no schema change (version 6 stands), no FFI
change, no new tool (the catalog stays 75). The core is not touched. Every
size toll below is paid FIRST and alone, as a pure move, on road map 2's
terms.

### 4a. The cache

`cache/speech/<media id>.bin`: one 32-bit float per **32 ms chunk of
SOURCE time** — 512 samples at 16 kHz, exactly `600000 × 512 / 16000 =
19 200` ticks, `MediaSpeech.chunkTicks`, written as the division as
`MediaPeaks.bucketTicks` is — from t = 0, `ceil(duration / chunk)` entries,
the last chunk zero-padded to 512 samples. It is the model's `probability`
for that chunk, pre-fader like a peak bucket; a forty-minute recording is
75 000 floats, 300 KB. Its marker is `cache/speech/<id>.complete.json`, a
sidecar holding the `CacheStamp`, which gains two fields — `speechModel`
(a string naming the asset, `"silero-vad-6.2.1-coreml-fp16-32ms"`) and
`speechChunkSamples` (512) — so a changed model or chunk rebuilds every
speech cache and nothing else. The post kind is `"speech"`; the reader
half is `MediaSpeech.Loader`, `MediaPeaks.Loader`'s shape with a `pending`
set, and its window arithmetic is `MediaPeaks`' — `sourceTick`, the floor
for a negative index and the reversed mirror — factored so `peak` and the
new `speechMax` share one `window(of:from:to:reversedPivot:bucketTicks:)`
rather than a third copy of the project→source conversion the app already
has two disagreeing spellings of.

The pass is `MediaImporter.speech(for:url:stamp:into:)` in a new
`MediaImporter+Speech.swift` (≤ 400 lines; an `extension MediaImporter`
as `MediaCacheFiles.swift` is), called from `generateCaches` after
`peaks` with the SAME stamp, inside the same `CacheLedger` slot, so a
relink's withdrawal and ordering hold for it without a line of new
bookkeeping. It opens its own `AVAssetReader` with the Transcriber's
extract settings (mono 16 kHz float — AVFoundation's downmix of a stereo
source, the same one the transcription trusts), never a temporary file,
hands every 512 samples to the wrapper, and writes the floats atomically,
the marker LAST. Its refusals mirror `peaks`': no audio track, no
duration, a reader that will not build or start → no marker, no `.bin`,
retried next open; a stale or partial cache is cleared BEFORE the decode
and the withdrawal posted at once, on `clearPeaks`' argument. One more
that `peaks` does not have: **the model fails to load** (a bundle without
the folder — the offscreen harness is one — or a Core ML failure) → the
pass writes nothing, posts nothing and logs once; the detector then
answers `voiceUnavailable` and the feature falls back to level with a
sentence (4c), never a crash. A reversed clip is read MIRRORED as its
peaks are, from the forward file's probabilities — presence of a voice is
near enough symmetric for a cut, and it is recorded as an approximation
in §5.

### 4b. The wrapper — `SileroVAD.swift`

A value-shaped final class (≤ 400): `init(modelURL:)`, the six constants
(16 kHz, 512, 64, 128, the input and output names), `probabilities(of:
[Float]) -> [Float]` carrying context and state exactly as the spike does,
and ONE static that knows the bundle (`SileroVAD.bundled()` →
`Bundle.main.url(forResource: "silero_vad", withExtension: "mlmodelc")`
under `app/Resources/Models/`, a `type: folder` resource in `project.yml`
on `Fonts`' precedent; `tools/proof/harness/build.sh` copies `Models` as
it copies `Fonts`). Nothing AppKit in it, so a probe compiled from
`app/Sources` drives it over a WAV by path. Compute units
`.cpuAndNeuralEngine`; q6 measured CPU-only identical, so a proof may pin
either.

### 4c. The rule — `SilenceDetector`

`Settings` gains `mode: Mode` (`.voice` default, `.level`) and
`voiceConfidence: Double` (0.5; clamped to 0.1…0.9, the range the model's
authors say to tune inside). The walk, the walls, the minimum, the padding
and the inward frame snap are UNCHANGED and in the same order; what
changes is one voice's answer at one step:

- **level** — `peak × envelope ≤ threshold`, today's test, byte for byte.
- **voice** — the voice is quiet at a step iff the MAX probability over
  the chunks the step touches is `< voiceConfidence` (the max, as the
  peak takes the max: the conservative reading for a destructive edit);
  the envelope is still consulted first, so a silenced voice is dropped
  from scope exactly as today and mute and solo still cost no code here.
- **the fallback** — a voice whose media's probabilities never reach
  `voiceConfidence` anywhere inside the segment's source window is judged
  by LEVEL instead and its media is named in `Outcome.judgedByLevel`. A
  tone, a music bed, a sound-effects track therefore protect a tick the
  way they do today, and road map 2's phase-3 fixtures detect what they
  did. The test is over the segment's window and not the whole file, so
  a long recording whose voice is in one half does not turn a quiet
  music cue in the other half into "no voice, judge by level" for the
  clip that plays only the cue.
- **pending** — a media whose `speech/<id>.bin` is not on disk is never
  quiet in voice mode (the posture `peaks` established: a missing cache
  must not read as silence) and is named in `Outcome.voicePending`, which
  the sheet says as it says "still analysing" today.
- **unavailable** — `Input` records whether the model loaded; when it did
  not, `.voice` is refused in the tool and the sheet opens on Level with
  the sentence.

`SilenceDetector.swift` is at 538 and the mode costs about ninety lines,
so its toll is paid first: the walls (`excludingNests`, `merged`,
`overlap`) and the directional frame snap move to
`SilenceDetector+Walls.swift`, a pure move.

### 4d. The sheet

`SilenceSheetController` gains a first row, **Judge by: Voice / Level**
(an `NSPopUpButton` over `Mode.allCases`, defaulting to Voice when the
model loaded and disabled on Level with the sentence when it did not);
the threshold slider stays and is labelled for what it now does in voice
mode ("Level, for clips with no voice:"); the note names media still
analysing for EITHER cache and media judged by level ("2 files hold no
voice and are judged by level"); `cacheChanged` re-reads on a `speech`
post as it does on a `peaks` post, while something is pending. The
candidate shading is unchanged. Nothing here is persisted, as nothing in
the sheet is today.

### 4e. The MCP mirror

`detect_silence` gains `mode` (`"voice"` | `"level"`, default `"voice"`)
and `voice_confidence` (number, 0.1–0.9, default 0.5, refused by name
with `mode: "level"` — a value the run could not use is refused, never
dropped). The result gains `mode`, `voice_confidence`, `judged_by_level`
(media ids) and `voice_pending` (media ids); `threshold_db`, `min_length`,
`padding`, `scope`, `ranges`, `clips` and `pending_media` keep their
meaning. `mode: "voice"` with the model unavailable is refused with the
sentence. The handler is `AgentServer+Silence.swift` (138); the catalog
entry grows in `AgentCatalog+Clips.swift`, which is at 957 and over the
cap and not in `reelcut-remaining.md` §3's ledger — so the phase pays it
first: the two audio tools' entries (`detect_silence`, `normalize_clip`)
move to `AgentCatalog+Audio.swift` on `AgentCatalog+Files.swift`'s
precedent, a pure move. The parity check needs nothing: no op, no tool.

### 4f. Files

| File | Now | After | What |
|---|---|---|---|
| `app/Sources/SileroVAD.swift` | — | ≤ 400 | the wrapper (4b) |
| `app/Sources/MediaImporter+Speech.swift` | — | ≤ 400 | the pass (4a) |
| `app/Sources/MediaSpeech.swift` | — | ≤ 400 | `chunkTicks`, `Loader`, `speechMax` |
| `app/Sources/MediaPeaks.swift` | 219 | ~260 | the shared window arithmetic |
| `app/Sources/MediaCacheFiles.swift` | 490 | ~550 | `speechKind`, URLs, clear/load, the two stamp fields |
| `app/Sources/MediaImporter.swift` | 571 | 572 | one call in `generateCaches` |
| `app/Sources/SilenceDetector+Walls.swift` | — | ~130 | **toll, first and alone** |
| `app/Sources/SilenceDetector.swift` | 538 | ~500 after the toll | `Mode`, the voice test, the fallback |
| `app/Sources/SilenceSheetController.swift` | 437 | ~500 | the popup, the note |
| `app/Sources/AgentServer+Silence.swift` | 138 | ~190 | two arguments, four result keys |
| `app/Sources/AgentCatalog+Audio.swift` | — | ~120 | **toll, first and alone** |
| `app/Resources/Models/silero_vad.mlmodelc/`, `LICENSE`, `PROVENANCE.md` | — | 640 KB | the asset (decision 1) |
| `project.yml`, `tools/proof/harness/build.sh` | | | the folder resource; the harness copy |
| `designs/reelcut-design.md` §5.6, §7.4, §11; `CLAUDE.md`; `app/CLAUDE.md` | | | the lockstep pass |
| `core/` | | | **nothing** |

### 4g. The proof

`tools/proof/silence2_proof.py` over MCP against `make app`'s binary, and
`silence2_probe.py` over a probe compiled from the whole of `app/Sources`,
on the tree's terms — a placement read back, or a number a mutant moves.
The script MAKES its fixtures (`say` and ffmpeg, the recipes in the spike's
README; `ffmpeg` at proof time, as the audio proofs already need) and the
truth is the −40 dBFS level run on the clean fixture's digital silence,
which is exact there.

Claims: **(1)** the clean fixture in voice mode finds both pauses within
+0.10 s at the start and +0.03 s at the end of the truth, edges INWARD
(asserted by sign); **(2) `hum3.wav`**: level mode at −40 answers no
ranges, voice mode answers both pauses on the same bounds — the headline;
**(3) `quiet2.wav`**: level mode at −40 answers six ranges, voice mode
two; **(4)** a tone with gaps (phase 3's own fixture shape) answers the
SAME ranges in both modes, byte for byte, and names the media in
`judged_by_level`; **(5)** phase 3's `phase3_proof.py` and
`phase3_silence_scope.py` score 121/121 and 8/8 unchanged against the new
binary with `mode` defaulting to voice — the fallback is what makes that
true, and it is a claim to run, not assume; **(6)** a muted or
solo-silenced voice clip proposes nothing in voice mode, the scope rule
surviving; **(7)** a nest wall survives; **(8)** a media with its
`speech/<id>.bin` withheld (the proof deletes it under the ledger's nose
and re-detects before the pass lands) is never quiet and is named in
`voice_pending`; **(9)** a reversed voice clip's pauses mirror; **(10)**
`voice_confidence` with `mode: "level"`, a value outside 0.1–0.9 and a
misspelt mode are refused by name; **(11)** `ripple_delete_ranges` of the
voice-mode answer exports a file whose decoded PCM equals the concatenated
words within the cut's frame snap (phase 3 proves the cut; this proves
the answer was the right one to send).

The probe: **(12)** the wrapper over the clean fixture reproduces a pinned
32 ms trace within 0.01 and its decisions at 0.5 exactly (q6 measured CPU
and ANE identical); **(13)** the pass writes the `.bin` then the marker,
with the stamp's two new fields, and a marker with a different
`speechModel` string rebuilds; **(14)** the withdrawal is posted before the
decode and `replaced` on the first post; **(15)** a file with no audio
writes nothing; **(16)** a missing model → `voiceUnavailable`, the sheet's
default Level, the tool's refusal sentence, no crash; **(17)** the popup's
rows and default, and `cacheChanged` observing both kinds, as structural
reads, since the harness cannot put up a sheet. No new chrome script: the
sheet is not photographable offscreen and the candidate wash is phase 3's
already.

Mutants, each named in the record with its score: probability forced to 1
(claim 2 finds nothing); the fallback removed (claim 4's tone answers
nothing in voice mode); the max over a step's chunks made the mean (claim
1's edges move outward); the state not fed back (claim 12's trace moves);
the context not carried (claim 12); `speechModel` dropped from the stamp
(claim 13's rebuild does not happen); the window test made whole-file
(claim 4's two-clip variant misjudges); `voice_confidence` accepted with
`mode: "level"` (claim 10). Every earlier proof re-run against the final
binary and quoted "against the N it had at the time".

### 4h. What only a person at the machine can check

- **A narrated screencast recorded by the app** (road map 3's recorder,
  microphone on) run through Voice mode, the truth marked by ear and the
  spans compared — q7 is why no file in hand can stand in for this.
- **A cut listened to across a voice-mode boundary**: whether 60–100 ms
  of offset lag plus 0.1 s of padding sounds like breathing room or like a
  clipped word, and whether the padding default should drop to 0.05 s.
- The sheet's note reading right when one file is pending and another is
  judged by level.

---

## 5. Limits recorded, not fixed

- A reversed clip's voice is read from the forward file's probabilities,
  mirrored (4a): presence is near enough symmetric, but a chunk boundary
  is not, so a reversed edge can be a chunk off where a forward one is
  not.
- The model's known weak material — voice-like instruments, singing,
  very high-pitched voices — is not this app's, and is not measured here.
- `quiet2.wav` lost its soft first word at that SNR (q6); a very quiet
  opening word after a long lead-in can read as no voice and be cut into.
  The padding is the only guard; a person at the machine decides whether
  0.1 s is enough (4h).
- The fallback's "never reaches the confidence anywhere in the window" is
  a single scalar over a window; a clip that plays one second of speech
  inside twenty minutes of music is judged by voice for its whole length.
  The scope popup is the escape.
- The cache is 16 kHz mono of AVFoundation's downmix; a voice panned hard
  to one channel of a stereo file is halved before the model sees it.

---

## 6. What the spike found in older ground

- **`SpeechAnalyzer` + `SpeechTranscriber` run on a file with NO
  speech-recognition grant** on macOS 26.5.1 — `authorizationStatus` stayed
  `notDetermined` and words came back — where phase 4's `Transcriber`
  documents `SFSpeechRecognizer`'s grant as the gate and refuses without
  it. Spec §11's sentence that `SpeechAnalyzer` "would earn the argument
  again — but only when the deployment target moves" now has a second
  reason beside the `async` one: it would also drop the grant. Not acted
  on; recorded for the day the target moves.
- The shipped −40 dBFS default marks nine tenths of the recorder's own
  microphone file silent (§1). That default was chosen against a `say`
  fixture with digital silence between its sentences, where every
  threshold from −40 to −60 finds the same spans — a fixture that could
  not have shown the failure.
- This ffmpeg's `sine` sits at −21 dBFS, as `tools/proof/README.md`
  records; a fixture "at −30 dB" is at −51 dBFS, which is why the hum
  fixtures are named by their measured floors above.

---

## 7. Not built, and why

- **An adaptive threshold** (q2): fixes the quiet microphone, is
  destructive under a hum; the field's "Auto" (Recut, AutoCut) is this.
- **SoundAnalysis** (q5): no asset to ship, no grant, a callback API —
  and edges a quarter second outward into the words, 15× slower than the
  model, and no speech heard in the one real mixed file. Its one merit
  does not buy a wrong edge.
- **Level-based edge refinement inside a voice-mode span** — walking a
  span's edges to the local floor within the model's lag. Designed, then
  dropped: the measured lag (+0.06…+0.10 s) is inside the padding, and a
  second edge rule would be a second thing to prove per fixture. Revisit
  only if 4h says the padding should go to zero.
- **Hysteresis** (onset 0.5, offset 0.35): moved no edge by more than a
  chunk on any fixture. One number, exposed, is simpler to explain.
- **The transcriber's word gaps** (q4), **Apple's `SpeechDetector`** (q3),
  **TEN VAD** (a license clause and no Core ML port), **libfvad** (a binary
  10 ms decision at 50 % recall in noise), **any Rust route** (spec §7).
- **Gemini** (q8, decision 5).
- **Persisting the sheet's mode** — nothing in the sheet persists today.

---

## 8. S1 — the record (written 2026-09-17, after the fact)

**`1c3e92e` (2026-09-15).** 23 files, +1343 / −211. From the commit's own
account; the plan above is kept as written.

- The second signal is Silero VAD v6.2.1 as a Core ML program, vendored
  COMPILED at 640 KB under its MIT notice, with
  `app/Resources/Models/PROVENANCE.md` naming the upstream tag, the
  conversion repository, the download's revision and a sha256 per file.
  Core ML is the runtime: no new dependency, no grant, no `async` exception,
  no deployment-target change.
- `SileroVAD.swift` is the streaming wrapper — 512 new samples and 64 of
  carried context per prediction, the LSTM state fed back, the remainder held
  across `feed` calls. `MLModel.prediction` is synchronous, which lets one
  class serve the cache pass and, through the cache, a detector on main.
  Availability is one process-wide `NSLock`-guarded reason; the first failure
  is kept and logged, and a marked-unavailable process never retries until
  relaunch.
- The probabilities are a per-media CACHE, never computed at feature time:
  `cache/speech/<id>.bin`, one float per 32 ms chunk, beside `peaks/` and
  stamped on the same terms; `SpeechStamp` WRAPS `CacheStamp` with the model
  name and the chunk size, so a model change rebuilds speech caches and no
  filmstrip. The pass runs AFTER `peaks` in `generateCaches`, so the peaks
  `.bin` withdrawal is never held behind a full-file decode and an inference.
- `SilenceDetector` gains a `Mode`, and the ORDER of its per-step test is
  the point: the gain FLOOR first (factored out of `level`), so a
  turned-down, faded or ducked clip is quiet in either mode before the model
  is consulted; then a media holding no voice anywhere falls back to level
  for its whole span; then a media whose speech cache has not landed is never
  quiet. `detect` stays pure and synchronous.
- The sheet gains a Judge by popup (its Voice row disabled, not removed,
  when the model cannot be used) and notes for pending speech and for files
  judged by level; `detect_silence` gains `mode` and `voice_confidence`,
  reports both back, and folds both waiters into `pending_peaks`.
- Two pure moves paid the size toll first: `SilenceDetector+Walls.swift`
  (the nest walls and the directional frame snap) and
  `AgentCatalog+Audio.swift`, whose two rows are spliced back at the same
  point in the catalog so `tools/list` keeps its order.

**Verified at the landing:** `make typecheck` 0 errors and the same 4
AVFoundation warnings, `make app` building, the catalog still 75 tools with
`detect_silence` and `normalize_clip` in their old positions, the startup
parity log EMPTY, the bundled model found and voice the default mode against
the built binary, the three new argument refusals exact, and phase 3's
`phase3_proof.py` 121/121 and `phase3_silence_scope.py` 8/8 unchanged — the
fallback is what makes a tone fixture answer what it always did.

**Owed, as of this record:** the phase's own proof instruments — §4g's
`tools/proof/silence2_proof.py` (11 claims) and `silence2_probe.py` (6 more)
with 8 named mutants — so the voice path's edges, the cache's stamp rules and
the wrapper's trace are unproved by a tracked instrument; the reader review;
and §4h's checks by a person at the machine.
