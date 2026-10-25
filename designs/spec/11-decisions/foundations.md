# Spec §11 — decisions: Foundations (M1–M3, road map 2)

Part of spec §11, *Decisions made — do not re-litigate*. The index of every decision is
[`README.md`](README.md).

- **AVFoundation, not ffmpeg.** Risk: MKV, WebM/VP9 and AV1-in-MKV do not
  open. Mitigation (M3, landed): an opt-in import step that shells out to a
  user-installed ffmpeg (present at `/opt/homebrew/bin/ffmpeg` on the
  development machine) to rewrap or transcode. The conversion is written to
  `~/Library/Application Support/Frame Job/Rewrapped/`, **not into the
  package**, for two reasons the `FFmpegRewrap.rewrapDirectory` comment
  spells out: opening an MKV from the Finder makes an UNTITLED document, so
  the import that needs a conversion is exactly the one with no package to
  put it in; and `fileWrapper(ofType:)` is a two-child whitelist whose one
  surviving location, `cache/`, is documented-regenerable (§5.6) — the last
  place for the only decodable copy of someone's footage. The name carries
  a digest of path, size and modification date, so a conversion is reused
  and invalidates itself. `RCFFmpegImport` chooses the policy and
  `RCFFmpegPath` the binary; with neither ffmpeg nor a cached conversion
  the import fails exactly as it did before the feature existed.
  Amended by #216-R: WebM and Matroska open by a built-in rewrap; ffmpeg
  remains the opt-in step for what that does not copy.
  Amended by #227: that step copies a constant-rate VP9 Profile 0 or 2
  video stream rather than re-encoding it, kept only when every frame of
  the copy is on its rate's grid.
  **Amended by NM-4** (rename R0):
  `~/Library/Application Support/Reelcut/Rewrapped/` is now
  `~/Library/Application Support/Frame Job/Rewrapped/`.
- **Custom compositor from day one** (M1 step 5). `AVVideoCompositing`
  has sharp edges — pixel-buffer pools, timing, `renderContextChanged`.
  Building the single-layer version first de-risks every later effect.
- **`AVPlayerLayer` under an overlay view**, not a self-driven `MTKView`,
  for the preview: A/V sync and scrubbing come from the player; the
  overlay maps through `videoRect`.
- **One JSON op entry point** (`rc_project_apply`) instead of one C
  function per op. Trade-off accepted: argument checking moves to
  Rust (`Err`) and to the typed Swift builders; in return the header is
  stable and the MCP catalog is the same table.
- **The plan-string compare** decides rebuild vs. refresh. Simple, and
  correct by construction because the plan contains exactly the
  structural facts.
- **Overlap rule**: at most one neighbour per side, each overlap ≤ half
  the shorter clip; larger overlaps refuse. Clips never push.
- **Ripple is timeline-wide** across unlocked tracks; straddling clips
  on other tracks stay put.
- **Freeze frame keeps sync** by inserting time across all unlocked
  tracks, and is a one-source-frame segment scaled in the composition —
  no image extraction.
- **Ducking is by clip extent**, not voice activity,
  so no audio analysis is needed for it.
- **Speed and pitch** come from `scaleTimeRange` and the time-pitch
  algorithm. Reverse is not native; M3 pre-renders reversed segments.
- **Text and shapes are described, not rasterized, in the model.** The
  recipe carries the description; the platform renders it (Core Text /
  CG). Measured text sizes live in a Swift cache, never in the model.
- **Time is 600 000 ticks/s.** Mixed source rates resolve at render, never
  in the model.
- **No left panel.** Media is an inspector tab. Revisit if libraries grow
  past a few dozen files.
- **`async`/`await` is allowed only in `MediaImporter`.** Everything else
  keeps Rasterize's synchronous AppKit discipline. Speech recognition did
  NOT earn a second exception when it landed: `SFSpeechRecognizer`'s
  callback API is complete for what a transcription needs (a result handler
  per hypothesis and a final one, plus a delegate method per second of
  audio processed for the progress bar), so `Transcriber.swift` uses it and
  the rule stands. `SpeechAnalyzer`, the macOS 26 replacement, is
  `async`-only and would earn the argument again — but only when the
  deployment target moves, and then as one more named file, never as a
  general licence. Screen recording (road map 3) did not earn one either:
  every ScreenCaptureKit and AVFoundation capture call it needs has a
  completion-handler form, and `ScreenRecorder` uses those.
  **Amended 2026-09-22, by W-8 (road map 8's W2): the deployment target
  moved to macOS 26 and speech recognition EARNED the named file this
  paragraph foresaw.** `SpeechEngine.swift` is the second place `async`
  is allowed, and the only one this phase adds: the engine
  (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`) is
  `async`-only, so the file runs it in a `Task.detached` and hands every
  caller a synchronous wrapper or a main-queue completion. `Transcriber`,
  the sheet and the tool stay synchronous. `SFSpeechRecognizer` is gone.
- **Transcription reads EXTRACTED audio, not the media file.** Each clip's
  own source window is written to a temporary mono 16 kHz WAV and the
  recogniser is handed that. Whether `SFSpeechURLRecognitionRequest` can
  read an arbitrary `.mov` is a question nothing in the framework's
  documentation answers and nothing here can measure — the grant needed to
  try it cannot be obtained by an app that is never frontmost — and a
  design that works on the `say -o` fixtures and fails on every real clip
  is the worst failure shape available. It pays twice besides: the work is
  bounded to what the timeline uses (a 20 s clip of a 30-minute recording
  is 20 seconds of recognition), and the time mapping loses its `in` term
  entirely. The framework's roughly one-minute ceiling per task is
  REPORTED, not chunked around; chunking at the silences `detect_silence`
  already finds is the recorded follow-up.
  **Amended 2026-09-22, by W-8 (road map 8's W2): the extracted audio
  stays, and the ceiling GOES.** `SpeechTranscriber` reads the same WAV
  through `AVAudioFile`, and W0 q1 found no ceiling (the last word of a
  613.7 s file ended at 612.6 s), so there is nothing to report:
  `Truncation`, `Outcome.truncations`, the sheet's sentence and the tool's
  `truncated` key are deleted, and chunking is no longer a follow-up.
- **Media is referenced, not copied**, by path + bookmark (not
  security-scoped; the app is not sandboxed). Consolidate is M3.
- **R2-1 — One composition audio track per source audio format**
  (kpgalligan/framejob#34, 2026-09-24). An audio plan track becomes one
  composition track per distinct source audio format, because the preview's
  tapped item does not play a track that changes format — measured: an
  `AVPlayerItem` over a tapped track holding an AAC segment then an LPCM one
  stalls at its playhead with no tap callback, while the same segments on
  two tracks play and the export's untapped reader always played both. The
  format is the source's stream description (format, rate, channels, flags,
  bit depth); a segment with no readable source joins the first family. The
  first family keeps the plan's id; later ones take ids past every plan id
  and the placeholder's (`CompositionBuilder.firstExtraTrackID`). The recipe
  never names an audio track, and the plan and its JSON compare are
  untouched: this is AVFoundation's decoder rule, applied in Swift, not a
  timeline decision.
