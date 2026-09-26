# Reelcut — road map 4: Remove Silences, second pass

**Status: BUILT, PROVED and REVIEWED — S1 landed in `1c3e92e` (2026-09-15),
§4g's two instruments on 2026-09-19, and the reader review 2026-09-20,
CLOSED on that date including its second sceptic pass and the residue that
pass left (§8).** The spike (S0) was RUN on 2026-09-13 and
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
- `speechIsCurrent` checks that `cache/speech/<id>.bin` EXISTS, not that it
  is the right length, and past a short one's end `MediaPeaks.window` answers
  nil, `speechMax` answers 0 and the moment reads quiet. No input but a hand
  edit of the cache file makes one — the buffer is always sized by
  `media.duration`, a relink does not re-probe that duration, and the pass
  writes the whole buffer or (since the reader review) nothing at all — so
  it is a limit and not a defect (§8, R2·3).
- `detect_silence`'s `min_length` and `padding` are read as given and the
  span BOUNDS are what land on the frame grid. That is the sheet's own
  arithmetic (§8, R1·1) and it means a caller can ask for a padding finer
  than a frame; what it gets is a cut whose ends are still on the grid, so
  the padding it asked for is honoured only to within one frame.

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

**The proofs (2026-09-19).** §4g's two instruments landed against the
UNMODIFIED tree at **59/59** and **61/61**, and score **61/61** over MCP
(claims 1–11) and **61/61** over the probe (claims 12–17) against the tree
the two fixes below left — `tools/proof/silence2_proof.py` and
`tools/proof/silence2_probe.py`, the second compiled from the whole of
`app/Sources`, with
`tools/proof/silence2_trace.json` — 325 chunks, keyed on the sha256 of the
DECODED samples of `clean.wav` — as claim 12's pin. `tools/proof/README.md`
has the per-claim account.

**What made the MCP half worth running** is that it does not measure the
voice answer against a tolerance. It carries a Python REFERENCE WALK of
`SilenceDetector.detect` + `refine` over `MediaPeaks.window`'s arithmetic at
the 32 ms grid, reads the probabilities the app itself wrote into
`cache/speech/<id>.bin`, and asserts the answer TICK FOR TICK — forward at 30
fps, at 100 fps where one frame is one bucket, and mirrored for a reversed
clip about the MEDIA's duration. Making that mirror exact cost one correction
to the plan as §4g wrote it: the walk has to carry the segment's own
`source_duration` (`evaluate.rs:229–248`) rather than assume it equals the
clip's duration, because a whole clip's duration is `snapped(media.duration)`
and the two differ off the frame grid. The truth itself is measured per run —
the −40 dBFS level pass over `say`'s digital silence — so nothing is pinned
to how long this host's voice happened to talk for.

**The ten mutants, each in a copy of the tree** (the app rebuilt in the
copy and its binary on its own port; the probe compiled from the copy; the
staticlib copied in unchanged, since every mutation is in `app/Sources`):

| Mutant | Score | What it took |
|---|---|---|
| probability forced to 1 (`SileroVAD.step`) | **33/59** | every voice row of claims 1, 2, 3, 4, 8, 9, 11 and phase 3's re-run |
| the level fallback removed (`detect`) | **52/60** | claim 4's TONE rows — the tone answers one span across the whole clip in voice mode — and claim 5 with it; the new head row PASSES, the merged span dropped from both sides by its `< V` filter |
| max → mean over a step (`speechMax`) | **54/59** | claim 1(a), **1(c) at 100 fps**, claim 9 and claim 11's precondition; nothing else |
| the window test made whole-file (`detect`) | **57/60** | claim 4's two-clip TONE rows alone: the tone half is no longer judged by level; the head row passes for the same reason |
| **the fallback keyed per MEDIA** (`detect`, the pre-fix read) | **59/60** | the new head row ALONE — the voice clip of a voice-then-tone file is judged by level, and the walk over its own segment says so |
| `voice_confidence` accepted with `mode: "level"` | **58/59** | claim 10's first refusal, and only that |
| the LSTM state not fed back (`step`) | **57/61** | claim 12(c) amplitude AND decisions, and 12(d) both ways |
| the 64-sample context not carried (`step`) | **59/61** | claim 12(c) and 12(d) amplitude; the decisions survive it, which is worth knowing |
| `speechModel` dropped from `SpeechStamp` | **53/61** | claim 13's three marker rows and the whole of claim 14 — a foreign marker no longer rebuilds |
| **`replaced` dropped from the withdrawal post** (`speech`) | **60/61** | claim 14's `replaced` row alone |

Five of those ten were not re-run after the two fixes below and are quoted
against the N they had **at the time** (59 and 61): the probability forced to
1, max → mean, `voice_confidence` accepted with `mode: "level"`, the LSTM
state, and the 64-sample context. The five that were re-run are scored
against the 60 and 61 of that day, on a tree rebuilt in a copy with this
run's own fixtures — and the MCP half's N is **61** since claim 1(d) landed
with the #22 review's fixes later on 2026-09-19, so every `/60` above is the
N it was measured at and none of those was re-run for the extra row.

**The sensitivity line claim 1(c) prints** (not scored) says the mean rule IS
visible on this host's fixture: at a 100 fps canvas it answers
`[(1734000, 2514000), (4110000, 4644000)]` where the max rule answers
`[(1734000, 2508000), (4116000, 4644000)]` — two edges, one at each pause —
so the max→mean mutant is scored on that row and needed no exemption.

**The earlier proofs, re-run against the final binary**, each quoted with the
N it had at the time: `phase2_proof.py` **86/86** (85 at the time),
`phase3_proof.py` **123/123** (121 at the time), `phase3_silence_scope.py`
**8/8**, `phase5_proof.py` **88/88**, `remaining_proof.py` **79/79**. Claim 5
runs the two phase 3 scripts INSIDE `silence2_proof.py` as well, because
`mode` defaulting to voice is what makes a tone fixture answer what it always
did and that is a claim to run rather than assume; their counts are printed
there and their FULL score is what is asserted, since a later road map adding
a row to one of them is not this phase's failure.

**Four deviations from §4g's text**, each recorded rather than worked around:
(i) §4g's "edges INWARD (asserted by sign)" holds at the START only — an END
may overrun the truth, because the model calls speech up to a chunk before
the next word and `snapDownToFrame` only takes an end DOWN to the grid, so
the bound is q6's own row plus one chunk (`OVERRUN` = 0.07 s on clean and
hum3, 0.10 s on quiet2) and the sign is asserted at the start alone;
(ii) claim 3's "six ranges" is a property of that fixture's pink noise, so
it is printed — it WAS six on this host — and the lead-in span q6 recorded
(the soft first word missed at that SNR, §5) is printed too, not scored; (iii) claim 12's pin is keyed on the samples'
sha256 rather than the file's, because ffmpeg's WAV muxer writes an
`ISFT Lavf<version>` tag and the bytes move with a brew upgrade while the
samples do not; a different `say` is a SKIP printed by name with both hashes;
(iv) claim 11 trims the clip to the last whole frame INSIDE the file before
exporting. Without that the clip's duration is `snapped(media.duration)`,
which rounds UP past the end of the file, so the plan plays the segment at
0.9990 and AVFoundation RESAMPLES it — two exports of the same material then
drift by about seventeen samples and the claim would be measuring the
resampler. At rate 1 the cut export is BYTE-identical to the uncut one with
the proposed spans excised, which is stronger than the tolerance §4g asked
for. The overrun itself is a core defect older than this phase, filed as
kpgalligan/reelcut#22 with the two fix shapes it has to choose between.
**Closed 2026-09-19**: the core now snaps a media clip's length DOWN at all
three sites that write it (spec §11), so a whole-file clip lands on the last
whole frame inside its file and the plan plays it at rate 1. The trim is gone
from claim 11, which asserts that length in its first row instead, and the
two rows that were tolerant are now a sample count and a BYTE comparison; a
build that keeps the nearest snap scores **57/61** there. The review of that
change asked for the coverage it cost: with every clip the script walks now a
whole-file clip at rate 1, `MediaPeaks.sourceTick`'s
`source_duration / duration` factor is an IDENTITY in every row, so claim
1(d) was added — the clean clip at ×2, where the two differ and the answer
is still the walk over that segment tick for tick. That row took the MCP half
from 60 to **61/61**, and a build with the factor dropped from `sourceTick`
scores **60/61**, taking 1(d) alone (both measured 2026-09-19). **Rewritten
2026-09-20** by road map 7 §10's phase B: at ×2 the segment used to be the
clamp's own 6 233 613 against a duration of 3 120 000 — a ratio of 1.99795,
because `set_speed` was one of the writers #22 did not cover — and the row
said so while that stood. `set_speed` now holds the duration it snaps to
what the file still holds AT THE NEW RATE (spec §11, D4-3), so the numbers
are 6 200 000 against 3 100 000 and the row asserts the ratio is EXACTLY 2.
Its two halves have swapped sharpness with that: the `× speed` in place of
the plan's ratio mutant is now EQUIVALENT, and what stays sharp is the
factor itself and the spans against the walk (road map 7 §10.8). A trim
cannot stand in for it:
at rate 1 the plan resolves `min(duration, media.duration − in)`, which a
shorter window only makes smaller.

**Two defects the instruments measured, FIXED 2026-09-19** (not committed
here), which is what took the MCP half from 59 rows to 60:

- **The level fallback is decided per VOICE, not per media.** `detect` built
  a `Set` of media that hold no voice and read it back per media, so in claim
  4's two-clip fixture the voice half of a voice-then-tone file was judged by
  level along with the tone half. It now builds one
  `[(voice: Voice, byLevel: Bool)]` by a single `scoped.map` and the walk
  passes `entry.byLevel` to `isQuiet`, so each scoped segment is judged by
  the window it actually plays (`SilenceDetector.swift`, `detect`). **The
  naming decision:** `Outcome.judgedByLevel` keeps its type and stays a list
  of distinct MEDIA — a media with one window judged by level and another by
  voice IS named, because the sheet's note and the tool's note name FILES and
  a per-segment list would name nothing a person can see. The three sentences
  say "in at least one clip … there" so the note is true of a mixed file
  (`AgentServer+Silence.swift`, `SilenceSheetController.swift`,
  `AgentCatalog+Audio.swift`; `app/CLAUDE.md` and spec §7.4's row follow).
  Claim 4's two-clip variant now SCORES the voice half: its spans are
  compared tick for tick against the reference walk over clip A's own
  segment, filtered on both sides to the spans ending STRICTLY before the
  split (`r[1] < ticks_of(VOICE_LENGTH)`). The filter is the row's honesty —
  the voice clip ends in a quiet run of its own (`clean.wav`'s last chunk,
  then digital padding to 11.000 s, about 0.63 s), and a build that judges
  the tone clip by voice merges that run past the split into one span the
  walk over clip A alone can never answer. 11.0 s is exactly 330 frames at 30
  fps, so on the fixed tree the run ends ON the filter's bound and `<` drops
  it from `found` and from the walk alike. The printed note says level mode
  answers something DIFFERENT before the split on this host, which is the
  row's power.
- **The speech withdrawal posts `replaced`.** `speech` clears a stale `.bin`
  and posts first; that post opens a pass replacing a file already on disk,
  which is exactly what the flag means, so it now carries it
  (`MediaImporter.swift`, `postCacheChange(…, replaced: true)`;
  `MediaCacheFiles.swift`'s two doc sentences name it as the flag's second
  carrier). `writeSpeech`'s ARRIVAL post still does not, and `peaks` still
  posts without it either way. Probe claim 14's row is §4g's own wording
  again: the FIRST post carries it, the SECOND does not. Nothing downstream
  moves — `replaced`'s only reader is `TimelineView.invalidate`, which acts
  on it for `thumbs` alone — and `remaining_probe.py`, which filters its
  `replaced` rows by kind, still scores 170/170.

**One limit the instruments measured and did not fix**, out of this phase's
scope and printed by the probe: `writeSpeech`'s own `.bin` is not
bit-identical to `probabilities(of:)` over the same file — 30 to 70 of 325 chunks differ by at
most 0.0022, because the pass reads with `alwaysCopiesSampleData = false` and
the runner's own reader does not, so the 48 kHz → 16 kHz converter hands the
two paths different block sizes. Every DECISION at 0.5 is the same, and
feeding `probabilities(of:)`'s samples through `feed` in 1000-sample buffers
with a `flush` answers it back float for float, which is the row the
streaming rules are actually proved on.

### The reader review (2026-09-20)

Four readers, one question each, then one independent sceptic. **The named
deviation:** road map 5 §4f asks for PARALLEL readers and earlier reviews put
every finding to three sceptics; this run is /litecode, which runs one agent at
a time, so the four readers were SEQUENTIAL single-context passes — each
finished and written into this section before the next started — and there is
ONE independent sceptic. Every reader tried to refute its own findings first,
by building the input and running it; nothing here is a vote.

**The four questions, verbatim** (road map 4 never wrote its readers' questions
down, so these are shaped on road map 5's and recorded here as the ones asked):

1. **The rule's arithmetic**: `SilenceDetector`'s spans against every clip
   shape — speed, reversal, a trimmed window, a clip inside a nest, a clip
   whose window #22 has now snapped down, frame rates off the 30 fps grid
   (30000/1001 and the recorder's 24981/1000), the level fallback per voice,
   min length and padding at the span edges.
2. **The cache and its lifecycle**: `cache/speech/<id>.bin` — the marker,
   withdrawal and arrival posts (`replaced`), relink and consolidate, a file
   swapped under an open sheet, a reader that will not build or start, a usage
   of the cache while it is being written, what a stale or truncated `.bin`
   answers.
3. **The Swift and the MCP mirror**: the sheet's state against the detector's
   outcome (`judgedByLevel` names MEDIA), undo names and the single undo step,
   `detect_silence`'s arguments against the sheet's controls, refusals in the
   rule's own sentence, the agent parity rules in `app/CLAUDE.md`.
4. **The proof and the tests**: which claims of `tools/proof/silence2_proof.py`
   and `silence2_probe.py` would pass against a build WITHOUT the feature, or
   with the level rule standing in for the voice rule; which of the recorded
   mutants overlap; what no claim reaches.

**The baseline, measured before anything was read:** `make test`, `make lint`,
`cargo fmt --check` and `make typecheck` (0 errors, the same 4 AVFoundation
warnings) clean, and the two instruments **61/61** and **61/61** against the
untouched tree, no skip. There is no R0·1.

**Reader 1 — the rule's arithmetic.** The walk was re-run against the app
tick for tick in shapes the suite does not carry: 30000/1001 and the
recorder's 24981/1000 (the one rate whose frame is NOT a whole number of
ticks — `Fps.frameDuration` truncates 24018.25 to 24018, and
`snapUpToFrame`/`snapDownToFrame` were brute-forced over 400 frames of it and
land on a real boundary in the right direction every time), a clip trimmed to
[1 s, 9 s) of its source, ×0.5 / ×1.5 / ×2, reversed × trimmed, reversed ×
speed, reversed at 24981/1000, and five (min_length, padding) pairs at the
span edges including padding that annihilates a run. **Every one matched the
reference walk exactly**, so the arithmetic itself is sound and the two
findings below are elsewhere.

- **R1·1** `app/Sources/AgentServer+Silence.swift:170-181` — `detect_silence
  {padding: 30000}` at the DEFAULT 30 fps ran with padding **40000**, and
  `{padding: 9999}` ran with **0** (measured: the spans come back two frames
  wider at each end than asked), because both DURATIONS went through
  `optionalTimeArg`, which snaps every tick to the frame grid; `min_length:
  45000` likewise ran as 40000. The sheet's own fields do not snap
  (`SilenceSheetController.silenceSettings` → `ReelTime.ticks(seconds:)`), so
  the tool that exists to mirror the sheet answered a different cut from the
  same request — and on `padding` in the destructive direction, eating the
  material the caller asked to keep. Both are read by `intArg` now and are
  reported back unchanged; the frame rule stays on the span BOUNDS, which
  `refine` still snaps. **FIXED** — `silence2_proof.py` §10b, six rows (the
  value echoed, and the spans the walk says at that value, for
  `padding: 30000`, `min_length: 45000` and `padding: 9999`); a copy with the
  two `optionalTimeArg` reads restored scores **75/79**.
- **R1·2** `app/Sources/SilenceDetector.swift:113,209` — two doc sentences
  said a media whose speech cache has not landed "is judged by" level (`Mode`)
  and is "judged by level until it does" (`Outcome.voicePending`). It is not:
  `isQuiet` answers `false` — never quiet — and no level test is run, which
  is what §4c decided and what claim 8 already measures (with the `.bin`
  withheld voice mode proposes NOTHING inside that media while level mode
  answers the two pauses). Prose only; both sentences now say what the code
  does, line for line so `SilenceDetector.swift` stays at its 595 and pays no
  toll. **FIXED** — the behaviour's row is claim 8, and a copy whose pending
  arm falls back to level, making the old sentence true, scores **77/79**,
  taking claim 8's "proposes NOTHING inside it" and §8b's with it.

**Reader 2 — the cache and its lifecycle.**

- **R2·1** `app/Sources/MediaImporter+Speech.swift:97` — `writeSpeech`'s
  read loop ends on a nil sample buffer, which means EITHER the track ran out
  OR the decode gave up part way, and `reader.status` was never asked. The
  rest of the zero-filled buffer then stayed at zero, zero is "nobody is
  talking", and the pass wrote the `.bin` and CERTIFIED it with a marker
  nothing would rebuild until the file's stamp changed. Input:
  `clean.wav` re-encoded as AAC with bytes 45 %–70 % of the container zeroed
  and the `moov` left intact, so AVFoundation reports the full 10.389 s and
  the reader gives up at 2.05 s — voice mode then proposed
  `[[2.1667, 10.2333]]`, **8.1 s of a 10.4 s file**. (A truncated WAV does not
  produce this: AVFoundation reads its duration off the bytes that are
  actually there, which is what the reader tried first.) `reader.status` is
  read BEFORE the cancel now — the cancel would make every status
  `.cancelled` — and anything but `.completed` writes no `.bin`, no marker
  and no post, which is §4a's own posture for a reader that will not build or
  start: the media stays `voice_pending`, is never quiet, and is retried on
  the next open. **FIXED** — `silence2_proof.py` §8b, four rows over a new
  `corrupt.m4a` fixture; a copy without the guard scores **76/79**.
  The LEVEL half of the same hole is in `MediaImporter.peaks`, whose file is
  604 lines and over the cap, so it takes nothing on: **FILED as
  kpgalligan/reelcut#23**, and §8b's last row asserts that level still
  proposes that tail, so the day #23 closes the row says so rather than
  passing in silence.
- **R2·2** `app/Sources/SilenceSheetController.swift:389` — `cacheChanged`
  returned early unless `pendingMedia` or `pendingSpeech` held something, so a
  post that arrived with NOTHING pending was dropped and the sheet went on
  showing spans measured from bytes that were no longer on disk. That is K13
  of the already-known list (`designs/reelcut-remaining.md` §5), recorded as a
  limit on the reason that **no proof could drive the sheet** — and
  `silence2_probe.py`'s claim 17 drives it through a real document and posts
  at it, so the reason was false and the guard was one line. Dropped.
  **FIXED** — `silence2_probe.py` claim 17, two rows: with both caches landed
  and nothing pending, the `.bin` under the open sheet is replaced by one that
  says "talking" at every chunk and a `speech` post is made — the readout goes
  to **No cuts** and the wash to 0 — then the original bytes are posted back
  and the two cuts return. A copy with the pending guard restored scores
  **64/65**, taking the first of the two.
- **R2·3** `app/Sources/MediaImporter+Speech.swift:24` — L4 of the plan's
  leads: `speechIsCurrent` checks that the `.bin` EXISTS and not that it is
  the right LENGTH, and past a short `.bin`'s end `MediaPeaks.window` answers
  nil, `speechMax` answers 0 and the moment reads quiet. No input but a hand
  edit of the cache file produces one: the buffer is always sized by
  `media.duration`, a relink does not re-probe that duration (K14) so the size
  does not move under it, and the pass either writes the whole buffer or (now)
  nothing at all. **REFUTED as a defect — recorded as a limit, §5.**

**Reader 3 — the Swift and the MCP mirror.**

- **R3·1** `app/Sources/AgentServer+Silence.swift:89` and
  `app/Sources/SilenceSheetController.swift:329` — the pending note DENIED
  the answer printed beside it. Input: `clean.wav` imported, both caches
  landed, then `cache/peaks/<id>.bin` deleted and `detect_silence` called in
  voice mode. It answers `[[2.9, 4.1667], [6.8667, 7.7333]]` — two spans
  inside media 2 — with `pending_peaks: [2]` and the note "Analysis is still
  running for 1 media file(s). **Nothing inside them is proposed for
  removal**; call again in a moment." Both halves of the reply are in the same
  JSON object and one of them is false: `pending_peaks` folds BOTH waiters
  (K21) and in voice mode a missing waveform does not silence a file — the
  model has landed and decides. The sheet's twin said the same thing on
  screen, over a timeline washed with the spans it was denying. The promise is
  now made about what the ANSWER shows: the waiters of the mode that ran,
  minus any media the reply already proposes a span inside
  (`Outcome.proposedMedia`), with a waveform-only waiter and a
  proposed-inside waiter each named for what it is. **FIXED** —
  `silence2_proof.py` §8c, seven rows, and `silence2_probe.py` claim 17, two
  more over the sheet; a copy with both old sentences restored scores
  **78/79** and **64/65**. The FIRST spelling of the fix promised "only about
  the media it holds for", which was still false by a second route, the gain
  FLOOR — measured and closed by the sceptic's pass, finding 2 below.
- **R3·2** `app/Sources/AgentCatalog+Audio.swift:52` — `mode`'s description
  still said voice falls "back to level per FILE that holds no voice
  anywhere", which is the read the 2026-09-19 fix above replaced: the fallback
  is per VOICE, over the clip's own source window, and the three result
  sentences were changed then while the argument's was not. Now "over any clip
  whose own source window holds no voice". **FIXED** (prose; the behaviour is
  claim 4's two-clip rows, which is what caught the code defect in the first
  place).
- **R3·3** `app/CLAUDE.md:320` — the file map spelled the gain FLOOR as
  "`peak × envelope`". It is not: the floor is the plan's ENVELOPE alone
  against the threshold (`gain(of:) > limit`), which is what makes a muted,
  faded or ducked clip quiet in either mode BEFORE the model is asked;
  `peak × envelope` is the level test that comes after it, and reading the
  rule the way that line wrote it would make the two steps one. **FIXED**
  (prose).
- **R3·4** `designs/reelcut-design.md` §7.4 — the normative row for
  `detect_silence` still read `{clips?, threshold_db?, min_length?,
  padding?}`. S1 added `mode` and `voice_confidence` and four result keys, and
  §4e's lockstep pass named §7.4 but did not reach it: §5.6's cache lines and
  §7.10's file table were updated, the tool's own signature was not. The row
  now carries both arguments, the confidence range and its refusal,
  `judged_by_level`, `voice_pending` and the fold into `pending_peaks`.
  **FIXED** (prose; the arguments themselves are claim 10's four refusals and
  §10b's six rows).

*Noticed in passing, no verdict:* with a nest on the timeline,
`detect_silence`'s `clips` names the INNER clip's id — 3 where the top level
holds only nest clip 6 — because the plan flattens a nest into one segment
per clip inside it and `segment.clip` is the inner id. It is consistent (the
id is accepted back as a scope and the nest wall then answers `[]`) and it is
the same flattening `Input.nests` and K11 are about, so it is recorded here
rather than filed. And `README.md`'s file-map row for the catalog still lists
`AgentCatalog.swift · AgentCatalog+Clips.swift · AgentCatalog+Files.swift`,
where the tree also has `+Audio` (road map 4's toll 2), `+Transitions` (road
map 5) and `+Declarations` (road map 7) — drift from three road maps rather
than this one's, left alone here and written down so the next pass through
that table has it.

**Reader 4 — the proof and the tests.** Two builds, each a copy of TODAY's
tree (the binary at `1c3e92e^` is not built and would measure nothing: it has
75 tools, writes no `cache/speech/<id>.bin`, and the probe names the S1 types
on 20 lines and cannot compile against it, so both instruments would ABORT and
every claim would read as "caught"):

- **W1, "without the feature"** — `MediaImporter+Speech.swift`,
  `probabilities[index] = value` → `= 0`. The pass still writes a `.bin` of
  the right length under a current marker, so both instruments run to the end;
  every window then reads 0, every clip falls back to LEVEL and the answers
  are the shipped rule's.
- **W2, "level standing in"** — `SilenceDetector.swift`, `isQuiet`'s voice arm
  replaced by `level(...) <= limit`, the model never consulted.

Each patch asserted its replaced text occurs exactly once; both ran on port
4872 in the copy. **No cell is `unreached`** — each instrument ran to its
count under each build, so nothing here is UNJUDGED.

| Claim | W1 | W2 |
|---|---|---|
| 1 the clean fixture (walk, truth, 100 fps, ×2) | fails (4) | fails (4) |
| 1e the recorder's 24981/1000 | fails (1) | fails (1) |
| 2 `hum3.wav`, the headline | fails (5) | fails (5) |
| 3 `quiet2.wav` | fails (4) | fails (4) |
| 4 a tone, both modes, the fallback | **passes** | **passes** |
| 4 voice THEN tone, two clips | fails (1) | fails (1) |
| 6 the scope rule in voice mode | **passes** | **passes** |
| 7 the nest wall in voice mode | **passes** | **passes** |
| 8 the speech cache withheld | **passes** | fails (1) |
| 8b a decode that stops part way | **passes** | fails (1) |
| 8c the waveform withheld | fails (1) | fails (1) |
| 9 reversed, the mirrored walk | fails (1) | fails (1) |
| 10 the refusals | **passes** | **passes** |
| 10b `min_length` and `padding` as given | fails (3) | fails (3) |
| 11 the cut and the export | fails (1) | fails (1) |
| 5 phase 3's own proofs | **passes** | **passes** |
| 12 the wrapper, four ways | fails (1) | passes |
| 12d the pinned trace | fails (2) | passes |
| 13 the `.bin` then the marker | passes | passes |
| 14 the withdrawal's order and `replaced` | passes | passes |
| 15 a file with no audio | passes | passes |
| 17 the sheet, open | fails (1) | fails (2) |
| 17 the cache withheld, `peaks` post | passes | fails (3) |
| 17 the cache withheld, `speech` post | passes | fails (3) |
| 16 a process with no model | passes | passes |

**Scores: W1 58/79 and 61/65; W2 56/79 and 57/65.**

- **R4·1** `tools/proof/silence2_proof.py` claim 11 — it PASSED under both
  builds, and §4g's own sentence for it is "phase 3 proves the cut; this
  proves the answer was the right one to send". It did not: it exported
  whatever `detect_silence` answered and proved the cut matched it, which a
  build with no voice rule at all satisfies. **FIXED** — the section now
  walks the spans it is about to cut over the app's own `cache/speech/<id>.bin`
  before exporting them, and the row is what W1 and W2 each take in the table
  above.
- **R4·2** neither instrument reached a canvas rate whose frame is not a
  WHOLE number of ticks. 30 fps is 20 000, 100 fps is 6 000 and 30000/1001 is
  20 020; the recorder's own **24981/1000** is 24018.25, which
  `Fps.frameDuration` truncates to 24018, and `snapUpToFrame` /
  `snapDownToFrame` compose the nearest snap with that truncated step —
  arithmetic nothing scored. Reader 1 measured it by hand over 400 frames and
  against the app and it holds, which is why this is a gap and not a defect.
  **FIXED** — `silence2_proof.py` §1e, three rows (the truncated step, the
  answer against a walk that computes the boundary from the RATE, and every
  bound a real boundary of a grid whose frames are 24018 and 24019 ticks apart
  by turns); a copy whose `refine` snaps to the NEAREST frame instead of
  directionally scores **74/79** and takes 1e's walk row with it.
- **R4·3** — an ANSWER to the question's first part, not a finding. The nine
  claims that pass under both are not defects and are not sharpened: 4's tone half and 5 are about the FALLBACK, which is the level
  rule by definition; 6 and 7 are about the scope rule and the nest wall,
  which are mode-independent and assert an answer a level build gives too; 10
  is about the ARGUMENTS; 13, 14 and 15 are about the cache pass's files,
  marker and posts, which W1 still writes and W2 does not touch; 16 is about a
  process with no model at all. Each is honest about its own subject, and a
  row that fails for a reason outside its subject would be a worse row.
  Recorded so the table above is not read as nine holes.
- **R4·4** — an ANSWER to the question's second part, not a finding: the
  overlap, read off §8's own table without re-running K22's five. The
  **64-sample context not carried** (59/61) fails a
  strict SUBSET of what the **LSTM state not fed back** (57/61) fails — 12(c)
  and 12(d)'s amplitude, where the state mutant takes the decisions too — and
  the **window test made whole-file** (57/60) fails a strict subset of the
  **fallback removed** (52/60), which takes claim 5 as well. Two overlaps,
  each with a strictly stronger partner, and neither needed a run to see. W1
  is the complement of the recorded **probability forced to 1** (33/59) and is
  the WEAKER of the two on the MCP half, because a probability of zero routes
  every clip through the level fallback where a probability of one simply
  makes nothing quiet.

**Where the review left the instruments.** `silence2_proof.py` **79/79** (61
rows when it landed; §8b four, §8c four, §10b six, §1e three and claim 11's
walk row are this review's — the sceptic's pass below took it to **83/83**)
and `silence2_probe.py` **65/65** (61 at the
landing; claim 17 gained two rows for the sheet's re-read and two for its
note). Both scored 61/61 on the UNTOUCHED tree before anything was read, so
the baseline is the landing's and nothing below is a pre-existing failure.
`make test`, `make lint`, `cargo fmt --check` and `make typecheck` (0 errors,
the same 4 AVFoundation warnings) are clean; no `.rs` file was touched.

**The mutants this review added**, each a copy of the tree under the scratch
directory on port 4872, every patch asserting its replaced text occurs exactly
once, the app rebuilt in the copy and the probe compiled from it:

| Mutant | Score | What it took |
|---|---|---|
| the two durations read through `optionalTimeArg` again | **75/79** | §10b's three echo rows and one of its three walk rows |
| a pending speech cache falling back to level | **77/79** | claim 8's "proposes NOTHING inside it" and §8b's |
| `reader.status` not consulted after the read loop | **76/79** | the whole of §8b but its level row |
| the old pending sentence, in the tool and the sheet | **78/79** and **64/65** | §8c's note row; the sheet's note row |
| `cacheChanged`'s pending guard restored | **64/65** | claim 17's swap row |
| `refine` snapping to the NEAREST frame, not directionally | **74/79** | claim 1's walk, §1e's walk, claim 9 and two of §10b |
| **W1**, the model's answer never reaching the cache | **58/79** and **61/65** | the table above |
| **W2**, the level rule standing in for the voice rule | **56/79** and **57/65** | the table above |

**Dependents re-run** against the final binary, because the files this review
touched feed them: `phase3_proof.py` **123/123** and
`phase3_silence_scope.py` **8/8** (inside claim 5), `remaining_proof.py`
**79/79**, `remaining_probe.py` **170/170** and `source_mirror_probe.py`
**40/40** — every one full. `e1_proof.py`, whose E1 section drives
`detect_silence` over a transition wall, scores **85/95 with 10 rows SKIPPED
by name**: it wants a SECOND instance built from the frozen `1c3e92e` tree on
a reference port and this run launched only one, so those ten are the
counts-and-version-6 rows that need it. Every row of it that calls
`detect_silence` PASSED, including the wall rows and the crossfade-dip row.

**Not judged here.** The sceptic's pass is the next step of this pipeline and
anything it did not reach stays UNJUDGED rather than refuted; §4h's three
listening checks are still a person's (`designs/reelcut-remaining.md` §4).

### The sceptic's pass over this review, 2026-09-20

The review above was re-read by a sceptic who ran both instruments himself
(79/79 and 65/65 on his own instances) and judged all eleven findings. Nine
he confirmed as they stood, one he confirmed as correctly REFUTED (R2·3);
**two of the review's own FIXES were broken and were fixed here**, with two
prose nits beside them:

- **Finding 1, a blocker — `app/Sources/AgentServer+Silence.swift`.** R1·1
  rightly stopped snapping the two durations, but `optionalTimeArg` had also
  CAPPED them at ±9.0e15 and `intArg` caps nothing, so
  `detect_silence {padding: 9223372036854775807}` reached `refine`'s
  `run.start + settings.padding` and KILLED the app (`EXC_BREAKPOINT`,
  "Swift runtime failure: arithmetic overflow", crash reports
  `Reelcut-2026-09-20-050302.ips` the sceptic's and `…-051240.ips` this
  pass's own, both inside `SilenceDetector.refine`). The schema publishes no
  `maximum` and the argument gate reads NAMES, so nothing else stood in the
  way. **FIXED**: both durations are bounded by `snappedTick`'s own ceiling
  and refused in a sentence naming the argument — `silence2_proof.py` claim
  10 gained the row, made to fail on purpose against the pre-fix binary,
  where it does not mis-answer but takes the socket down with the app.
  **The SHEET cannot reach it**: `minimumSeconds` and `paddingSeconds` clamp
  to `minLengthRange` (0.05–10 s) and `paddingRange` (0–2 s) and `clamp`
  answers the lower bound for a non-finite field, so the guard belongs on
  the tool and the arithmetic needs none at its root.
- **Finding 2, a should-fix — the pending note, again.** R3·1's replacement
  still denied ranges printed beside it, by a second route: the gain FLOOR is
  asked BEFORE either cache (`isQuiet`), so a clip the mix has turned down,
  faded or ducked is quiet with nothing on disk at all. Measured pre-fix, a
  clip at `volume: 0.001` with its speech cache withheld answered
  `ranges: [[60000, 6160000]]`, `voice_pending: [2]` and "… **Nothing inside
  them is proposed for removal.**" **FIXED** at the root the two notes share:
  `SilenceDetector.Outcome` now carries `proposedMedia`, the media a span in
  this answer actually lands inside, and the promise is made only about a
  waiter that is NOT one of them — the rest counted in a clause of its own.
  That held for the tool and for the sheet's LEVEL branch when this was
  written; the sheet's voice-mode WAVEFORM line was one branch short of it
  until the residue pass below closed that too, and it is true of the code as
  it now stands. Three rows landed at the foot of `silence2_proof.py` §8c,
  and MEASURED against the pre-fix binary only ONE of them fails: the NOTE
  row. The other two (`voice_pending == [media]` and `spans != []`) fix the
  setup the note is read in and pass pre-fix — exactly what the pre-fix
  measurement in this same bullet shows (`ranges: [[60000, 6160000]]`,
  `voice_pending: [2]`).
- **Finding 3, a nit — `SilenceDetector.swift:209`.** R1·2's replacement said
  a pending media is "never quiet" without qualification, where the floor can
  make it quiet with no model at all. Restored to "never quiet **by the
  model**, and not judged by level either". **FIXED** (prose).
- **Finding 4, a nit — the note's waveform clause.** With no blocked waiter
  it read "For **the rest** it is the WAVEFORM …" after a sentence that was
  not printed. Each clause now names its own count ("that file", "them",
  "2 of them"), and §8c's two note rows assert the WHOLE sentence rather than
  a substring, so the shape of the note is scored and not just a phrase in
  it. **FIXED**.

**The size toll it cost.** `SilenceDetector.swift` was at 595 of 600 and
`Outcome.proposedMedia` needed room, so `refine` and its doc moved to
`SilenceDetector+Walls.swift` — the pure move road map 4 §5 had already
planned as Toll A, `private static` → `static`, the file's header sentence
naming it. The detector is **586**, `+Walls` **178**, and no other file grew
past its cap (`AgentServer+Silence.swift` 253, `SilenceSheetController.swift`
528).

**Verified after the fixes**, on this pass's own instance (port 4893, killed
by PID; `grep "Reelcut: "` printed nothing): `make test`, `make lint`,
`cargo fmt --check` clean, `make typecheck` 0 errors and the same 4
AVFoundation warnings, `make app` BUILD SUCCEEDED, `silence2_proof.py`
**83/83** and `silence2_probe.py` **65/65**. No `.rs` file was touched.

### The second pass's residue, closed 2026-09-20

The sceptic's pass above ended `fix-required` with one should-fix and four
nits, and that pipeline runs no second fix pass. They were closed here, in
the tree, on the same day. What each was and what closed it:

- **Should-fix — the sheet's voice-mode WAVEFORM line
  (`SilenceSheetController.swift`).** Finding 2's fix was one branch short:
  that line said "Anything inside it that holds no voice is left alone until
  it lands" without ever asking `proposedMedia`, so a ducked clip whose
  window holds no voice had its whole span proposed by the gain FLOOR while
  the sheet denied it. MEASURED on the pre-fix binary, `tone.wav` at
  `volume: 0.001` with its waveform withheld: the sheet read "1 cut ·
  removes 00:00:09:24" over "…is left alone until it lands". **FIXED** by a
  new `waveformPromise()` beside `promise(about:)`, which HEDGES — "…, unless
  the mix already turns it down far enough to be quiet." — when some media is
  in `pendingMedia ∩ proposedMedia ∩ (judgedByLevel ∪ voicePending)`, and
  answers the plain sentence otherwise.
- **The DECISION, against the sceptic's suggested fix.** He proposed routing
  that branch through `promise(about:)`, as the level branch does. It is not
  routed there. That helper picks its arm by `proposedMedia` membership
  (`SilenceSheetController.swift:383-387`), and in the `afterPeaksGone`
  state — `clean.wav`, un-ducked, speech landed, waveform withdrawn — the
  media IS in `proposedMedia`, because the MODEL proposes 2 cuts inside it.
  The helper would therefore answer "What is proposed inside is quiet in the
  MIX — turned down, faded or ducked", which is false: nothing there is
  turned down. The MIX arm is the false one; the "Nothing inside is proposed
  for removal yet." arm is not (it is reached only with nothing proposed
  inside). **No existing row caught the rejected route**: claim 17's
  `afterPeaksGone` row in `silence2_probe.py` forbids only the "Nothing"
  substring and would
  have PASSED under it — which is why a second `afterPeaksGone` row
  forbidding `quiet in the MIX` was added, and mutant (e), the rejected route
  itself, is what fails it. `promise(about:)` stays sound for its two
  existing callers: a missing speech cache, or a missing waveform in level
  mode, blocks EVERY clip of that media, so whatever is proposed inside one
  IS the floor's.
- **The gate's `voicePending` arm, and the state it exists for.**
  `SilenceDetector.swift:419-421` returns `(voice, false)` for a voice whose
  speech cache is missing BEFORE `judgedByLevelMedia.insert` at :428, so a
  ducked clip with NEITHER cache on disk is proposed by the floor
  (`isQuiet`, :559) and is in `pendingMedia`, `voicePending` and
  `proposedMedia` but never in `judgedByLevel`. A hedge gated on
  `judgedByLevel` alone would miss it. Probe mode `ducked` reads two states
  for exactly this reason, and mutant (d) — the arm dropped — fails the
  second and passes the first.
- **Nit — `silence2_proof.py` claim 10.** Only `padding`'s ceiling was
  scored, so a build that kept the guard on one duration and dropped it on
  the other still scored full. Three rows added: `min_length` at the ceiling
  plus one, and a NEGATIVE value of each, all by the rule's own sentence.
- **Nit — `AgentCatalog+Audio.swift`.** Both durations published `"type":
  "integer"` and no bounds while their neighbours published theirs, so the
  ceiling lived only in a refusal sentence and the gate reads NAMES. Both now
  publish `"minimum": 0` and `"maximum": AgentServer.durationCeiling` (the
  one spelling: `durationCeiling` lost its `private`) and each description
  names the range. A fourth claim-10 row asserts what `tools/list` publishes.
- **Nit — `AgentServer+Silence.swift`'s `waveformOnly` clause.** The mirror
  image of the defect just fixed: it claimed "spans inside them ARE proposed
  here" without intersecting `proposedMedia`. It now splits that set and ends
  one of three ways, and where the proposed half is judged by level it adds
  " A clip there that holds no voice is proposed only where the mix already
  turns it down far enough to be quiet." A fixture CAN reach it: a tone file
  (no voice anywhere, so judged by level) with its waveform withheld proposes
  nothing, and ducked to `volume: 0.001` with the same waveform still missing
  proposes its span. Four rows at the foot of `silence2_proof.py`'s
  `tone_part`, on its own session. The clause needs no `voicePending` arm — a
  voice waiter is in `waiter` and never in `waveformOnly`.
- **Nit — this document.** Finding 2's two sentences above are amended: what
  the pre-fix binary actually failed was the NOTE row alone.

**The limit this leaves.** Both notes are MEDIA-granular. `proposedMedia`,
`judgedByLevel` and `voicePending` are sets of media ids, so neither the
sheet nor the tool can say WHICH clip of a file the mix made quiet; the
sheet's waveform line therefore HEDGES ("unless the mix already turns it
down far enough…") instead of naming the clip, and the tool's clause counts
files. A per-voice answer needs a new `Outcome` field and
`SilenceDetector.swift` is at 586 of 600, so it would cost a size toll — it
is not owed by anything here, and it is recorded so the next reader knows the
sentence is a conditional on purpose.

**Which rows failed PRE-FIX**, measured on the unmodified binary before any
of the three Swift changes went in, not predicted:

| Instrument | Score pre-fix | The rows that failed |
|---|---|---|
| `silence2_proof.py` | **88/91** | the two `tone_part` note rows, and the claim-10 row that reads the published schema |
| `silence2_probe.py` | **74/76** | the `duckedNoPeaks` hedge row and the `duckedNoCaches` hedge row |

The other six new rows PASS pre-fix on purpose: three fix the state a note is
read in, two under `afterPeaksGone` are what the mutants below fail, and the
three claim-10 refusals are guards against a guard being dropped.

**The mutants**, all five in ONE copy of the tree under the scratch
directory, each patch asserting its replaced text occurs exactly once, the
app rebuilt in the copy on port 4911 and the probe compiled from it:

| Mutant | Score | What it took |
|---|---|---|
| (a) `min_length`'s guard deleted | **89/91** | claim 10's two `min_length` rows |
| (b) `padding`'s `>= 0` deleted | **90/91** | claim 10's `padding: -1` row |
| (c) `waveformPromise()` hedging always | **75/76** | the `afterPeaksGone` "no hedge" row |
| (d) the gate's `voicePending` arm dropped | **75/76** | the `duckedNoCaches` hedge row alone — `duckedNoPeaks` still passes |
| (e) the waveform branch routed through `promise(about:)` — the rejected fix | **73/76** | the `afterPeaksGone` `quiet in the MIX` row and both hedge rows |

**Verified after the fixes**, on this run's own instances (4907 and 4909,
killed by PID, one instrument each; `grep "Reelcut: "` printed nothing on
either): `make test`, `make lint` and `cargo fmt --check` clean,
`make typecheck` 0 errors and the same 4 AVFoundation warnings, `make app`
BUILD SUCCEEDED, `silence2_proof.py` **91/91** (with `phase3_proof.py`
123/123 and `phase3_silence_scope.py` 8/8 inside claim 5),
`silence2_probe.py` **76/76** and `op_argument_proof.py` **116/116** — the
last re-run because item 4 changed a published schema, and unchanged as
expected: `detect_silence` is an APP-STATE tool, so parity part 3 reads only
object/properties/required, part 5 skips non-ops, the gate reads names, and
that script's section 2 walks op tools only. No `.rs` file was touched.

**Filed, not fixed:** kpgalligan/reelcut#24 — a clip's `start` is bounded at
9.0e15 per CALL and not cumulatively, so about 1020 successive maximum-delta
`move_clip`s walk it toward `Int64.max` and the app dies in
`ClipSnapshot.end` (`app/Sources/ProjectSnapshot.swift:1700`) during
`TimelineView.rebuildLayout`. The core saturates
(`core/src/edit_clip.rs:557`, `clip_end` :95) and Swift does not. Reproduced
once by the sceptic (PID 19353) and NOT re-run here. Labelled `bug` and not
`ready-for-agent`: where the bound belongs — a ceiling on `start` in the
core's op, or overflow-safe arithmetic in the app — is a spec §11 decision.

**The residue pass's own review (2026-09-20) passed with three notes, closed
by hand.** One of them is a limit and stays: the tool note's THIRD ending in
`AgentServer+Silence.swift` ("spans inside N of them ARE proposed here and
nothing inside the other M is") is UNSCORED. Both fixtures hold a single
waveform-waiting media, so no row and no mutant reaches the mixed case; a
row for it needs a document with two such media, one ducked. The other two
were a line citation that this pass's own edit had moved (now cited by
name) and `tone_part`'s last rows changing their session in place (now
marked at the site so nothing is appended below them).

**Owed, as of this record:** §4h's checks by a person at the machine
(listed in `designs/reelcut-remaining.md` §4), kpgalligan/reelcut#23 — the
LEVEL half of R2·1, which `MediaImporter.swift`'s size cap kept out of this
review — and kpgalligan/reelcut#24, filed above and outside S1 entirely.

## 9. Issue #23 — peaks publication after a complete decode (2026-09-21)

**Decision:** spec §11 S1-23. A waveform marker now certifies a completed
selected-audio-track reader, valid Float32 PCM ingestion and coverage of every
nonempty target edit. Genuine zero samples count as audio, and a record whose
duration differs from the selected sound track uses the record only to size the
100 Hz payload. The shared `CacheStamp` and its fields are unchanged. Only the
peaks sidecar is versioned: `{ "source": CacheStamp, "version": 1 }`. Missing,
legacy, future and malformed peaks markers, and malformed payloads, are
unavailable immediately; a normal cache pass withdraws them before awaited
track loads and rebuilds them. Thumbnail, speech and paid transcript stamps are
not migrated or rewritten by this change.

**Separate size gate.** At baseline `e1411be701442878e12becd85a4cbe8424f6a909`
the tree was clean, `MediaImporter.swift` was 604 lines and
`MediaCacheFiles.swift` 556. The synchronous reader/writer moved to
`MediaImporter+Peaks.swift` and the bucket accumulator moved verbatim to
`MediaPeakBuckets.swift` before any behavior changed. The exact stage diff is
in the litecode handoff's `04-pure-move.patch`; no commit was made. At that
stage the four files were 580, 478, 39 and 82 lines. The separate gate passed:
`make typecheck` (zero errors, four baseline AVFoundation warnings), `make app`
(BUILD SUCCEEDED), `remaining_probe.py` 170/170, `remaining_proof.py` 79/79
and `phase3_proof.py` 123/123, each MCP script on a fresh owned Release app
with no `Reelcut: ` parity complaints.

**Coverage boundary.** `PeakBuckets` places maxima at each accepted buffer's
presentation timestamp and coalesces consumed intervals. Its two outer-edge
allowances are local to each decoded outer edge: one PCM frame or a genuinely
fractional timestamp unit, and one fractional target-boundary unit, whichever
is larger. Exact integer boundaries (for example 0/1 or 1/1) add no timebase
slack. Exact full coverage needs no allowance, even on a coarse fractional
target grid. An edge shortfall is accepted only when its own allowance is
smaller than one 10 ms bucket. Internal gaps get no boundary allowance.
This distinction was measured: a complete 48 kHz WAV with its final buffer
omitted was wrongly certified when `0/1` gave a one-second slack; the corrected
source probe rejects both a missing final buffer and a missing middle buffer.
A valid ffmpeg AAC with a 228 ms empty edit and a 1022 ms nonempty target
has a 1.250 s track extent at a 1 ms target timebase, while AVAssetReader
returns 59,968 frames through 1.249333 s. Its 32-frame/0.667 ms end
shortfall fits one target timebase unit and is accepted. A delayed PCM MOV with
an actual 250 ms empty edit and an exact 1.250 s decode also passes. A
truncated WAV whose header claims a longer file is qualified from
AVFoundation's physically shortened selected-track extent (0.600 s here),
not treated as proof that its header was authoritative.

**Verification record.** The focused source probe compiles actual app sources,
awaits the real importer pass, reads back the marker and payload, and compares
all 100 buckets of each authored 44.1/48 kHz mono/stereo PCM fixture against
an independent Python frame count. It also covers AAC, genuine zeros,
record/track duration mismatch, legacy migration and inode reuse, nil stamp,
malformed and missing markers/payloads, corrupt middle AAC, a declared short
PCM block, nonfinite samples, and completed-but-uncovered sample streams.
The built-app proof checks corrupt media through level and Normalize,
unchanged project JSON, real silence, healthy normalization and legacy cache
withdrawal/migration. Its normal-pass trigger is a second imported media;
`relink_media` to the already-linked path correctly answered identity and was
not used as a fake trigger.

**Initial implementation gate:** `make test` and `make lint` passed; `make typecheck` had zero
errors and the four baseline AVFoundation warnings; `make app` printed BUILD
SUCCEEDED. The final pristine `peaks_probe.py` scored **77/77** (no skips).
`remaining_probe.py` scored **170/170** and `source_mirror_probe.py` **40/40**.
Four fresh owned Release apps, ports 5410–5413 with `RC_ASSEMBLYAI_KEY`
unset and zero `Reelcut: ` parity complaints, scored `peaks_proof.py`
**21/21**, `remaining_proof.py` **79/79**, `phase3_proof.py` **123/123** and
`silence2_proof.py` **91/91**, respectively. No paid request ran. These checks
read the current binary after the final product edit. `git diff --check`
passed at handoff.

**Made to fail.** Four source-copy mutants were run sequentially against the
71-row probe version, all with successful Swift builds and named behavioral
failures. Removing the reader-status guard scored **70/71** (published after
`.failed`); removing coverage and ingestion guards **67/71** (missing final,
missing middle, nonfinite and short PCM buffers published); accepting a bare
legacy marker **70/71** (false-silent cache available immediately); requiring
a positive bucket **68/69** (genuine silence not published, with its two
dependent value rows inapplicable). The later 77-row pristine probe only added
positive controls for an actual nil-stamp pass, a valid-source future marker,
marker-write rollback and >1.0 magnitude; the four assertions killed by the
mutants were unchanged. Exact mutant logs and the final pristine output are
named in the litecode handoff's `04-checks.txt`.

**Owed:** §4's human listen and visual waveform check on real footage. The
instruments do not claim waveform quality on every codec or fix source
changes that preserve both file size and modification second. An edge
shortfall of a 10 ms bucket or more cannot be certified; the waveform stays
pending instead of publishing speculative silence. Exact full coverage is
certifiable on coarse metadata grids.

**Review fix (2026-09-22):** The first implementation still let one decoded
`0/1` timestamp enlarge every edge's allowance, and rejected exact coverage
on a coarse fractional target grid. Coverage now retains the PCM-frame and
genuinely fractional timestamp precision at each outer edge, checks exact
coverage first, and caps any edge-shortfall allowance below one bucket. The
source probe's completed-stream 0/1 missing-tail and exact coarse-target
publication/readback controls score **80/80**. Two sequential source-copy
mutants each compiled and failed its named control (**79/80**); a final
pristine rerun scored **80/80**. `make typecheck` retained zero errors and
four baseline warnings, `make app` succeeded, and the fresh owned Release
app's peaks MCP proof scored **21/21** with zero startup parity complaints.
The earlier Rust and unrelated proof gates above remain valid for unchanged
paths; §4's hands-on waveform check remains owed.

**Final #23 review (2026-09-22):** The litecode handoff's
`01-issue-23/07-review-2.md` records `verdict: pass` with no findings after
the review fix. The completed-reader probe scored 80/80, both focused mutants
built and failed at 79/80, and the fresh Release app peaks proof scored 21/21
with no parity complaints. The human waveform check above remains owed.
