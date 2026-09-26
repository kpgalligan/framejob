# Spec §11 — decisions: Remove Silences (road map 4)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **The silence detector's second signal is a voice-activity model, and
  the model is Silero VAD v6.2.1 as a Core ML program** (road map 4's S0/S1).
  It is the app's first ML asset. It is vendored COMPILED
  (`silero_vad.mlmodelc`, 640 KB, FP16) with its MIT notice and a
  provenance file naming the upstream tag, the conversion's repository and
  the download's revision, so a re-conversion from the MIT upstream with
  coremltools is a documented option and not the only route. Core ML is the
  runtime; nothing else is added.
- **Edges come from the model's own 32 ms grid, inward; the level rule is
  the judge only where no voice is found.** No adaptive threshold, no
  level-based edge refinement: the measured edge error is inside the
  padding the feature already keeps. (The unit of "where" is the CLIP's own
  source window, not the media — a file that is speech then music is judged
  by the model over one clip and by level over the other, and is named in
  `judged_by_level` for the second; road map 4 §8, 2026-09-19.)
- **The probabilities are a per-media CACHE, never computed at feature
  time.** `cache/speech/<media id>.bin` beside `peaks/`, stamped and marked
  on the same terms (§5.6), written by `MediaImporter`'s pass — so the
  model runs where `await` is already allowed and `MLModel.prediction` is
  synchronous anyway. **No new `async` exception, no `@available`, no
  deployment-target change.**
- **Voice is the default mode** for the sheet and for `detect_silence`;
  level stays as a mode and as the fallback, unchanged in its arithmetic,
  so a project whose sound is tones (road map 2's phase-3 fixtures are)
  detects exactly what it did.
- **No network model in the silence path.** A transcript-level edit is
  where such a model would go, and that is a separate item on a later list.
- **S1-23 — A peaks marker certifies a complete selected audio-track decode.**
  The waveform is trusted only when the reader completes, every decoded PCM
  buffer is usable, and consumed frames cover every nonempty presentation
  interval of the selected audio track. Genuine zero-amplitude frames count
  as decoded audio. Gaps in the track's edit list remain silent; the media
  record's duration may differ from the track's duration after a relink or
  when video outlasts sound, so it is a storage bound, not a coverage oracle.
  Exact decoded coverage is valid on any track timebase. A shortfall at an
  outer edge may use only that edge's PCM-frame and fractional CMTime rounding
  precision, strictly less than one 10 ms waveform bucket; internal gaps
  receive no allowance.
  The peaks marker alone changes to a versioned wrapper around the existing
  `CacheStamp`; a missing, legacy, unknown or malformed peaks marker is
  unavailable immediately and rebuilt on the next normal cache pass. This
  does not change thumbnail, speech or transcript cache identities, project
  format or the provider upload decision. A failed decode writes no usable
  waveform and remains retriable.
