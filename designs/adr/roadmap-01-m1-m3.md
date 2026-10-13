# M1–M3: the spec's milestones, built and proved

- **Status:** Built (M1 2026-09-05, M2 and M3 2026-09-06, commit `d3fbaa0`); closed. Every
  feature in spec §10's milestone list is implemented and was verified against a running binary.
- **Original:** `archive/roadmap-1.md` (118 lines) — sections cited below as "orig §x" refer
  to it. The per-milestone narrative it points at is `archive/milestones.md`, condensed in
  `designs/adr/milestones-record.md`.
- **Spec decisions:** relies on the unnumbered M1-era entries at the head of spec §11 — AVFoundation
  not ffmpeg (opt-in rewrap, conversions outside the package); custom compositor from day one;
  `AVPlayerLayer` under an overlay view; one JSON op entry point; the plan-string compare for
  rebuild vs refresh; the overlap rule; timeline-wide ripple; ticks at 600 000/s; media referenced
  not copied; `async` confined to named files. No IDs were minted here. Spec §1's non-goals are
  its boundary (orig §4), since amended: screen recording is IN (spec §11, road map 3) and
  graphics amend the plugin non-goal (G-1, G-2).

## Context
Road map 1 was the companion to the spec while M1 (Cut), M2 (Compose) and M3 (Polish) were
built. It closed with every spec feature in, and what was left was not features but the half of
spec §10's acceptance tests only a person can run, plus a short list of known limits. It never
overrode the spec; what came after is road maps 2 onward.

## Decisions
- **Verification is the built binary, not the code** (orig §1, §5). Every "landed" claim was a
  rendered-frame byte comparison, a measured audio figure or a parsed file (`ffprobe` chapters,
  a GIF's descriptors), driven over MCP. This is the standard every later road map inherits.
- **`ExportWriter` replaced `AVAssetExportSession` outright** (orig §1). Two writing paths would
  have made chapters, bitrate and output size depend on which one ran. Bitrates measured within
  3–7 % of the request; chapters listed by `ffprobe` in mp4, mov and m4a.
- **GIF and APNG are presets like any other, written by ImageIO** (`avf_preset: null` routes to
  `ExporterImageSequence.swift`), refusing past 600 frames rather than truncating.
- **Effects are compositor passes with an exact bypass** (orig §1): shadow (mask → Gaussian blur →
  tinted quad; `distance`/`blur` in source pixels × layer scale; `angle` degrees from the right,
  counter-clockwise), filters, spotlight, reflection, chroma key. Each neutral setting is
  byte-identical to none — that is what makes adding one safe for existing projects.
- **A nest renders by flattening into instances** that the recipe, audio and transition code all
  consume, clipped to the nest's frozen canvas. Nesting is byte-identical to its contents; unnest
  is the identity (fresh ids). Editing *inside* a nest was left for later (orig §3.1; done by
  road map 2's phase 9 as an op `scope`).
- **Reverse is a cached render, substituted per clip** (`cache/reversed/<media>-<digest>.mov`
  in the package), so a boomerang is one media and two clips.
- **Audio DSP (pan, compressor, noise reduction) runs in one `MTAudioProcessingTap` on the mix
  that playback and export share.** Pan is constant-power normalised to unity at centre, so 0 is
  an exact bypass; neutral settings are bit-identical.
- **SRT import, Consolidate Media and ffmpeg-assisted import** landed on spec §11's terms: a
  consolidated package reopens after the originals are deleted and it is moved; an MKV opens after
  a rewrap and fails exactly as before with no ffmpeg.

## What it built — where it lives now
- Export: `app/Sources/ExporterWriter.swift`, `ExporterImageSequence.swift`,
  `core/src/export.rs` + `export_table.rs` + `export_overrides.rs`.
- Compositor and effects: `app/Resources/Shaders/Compositor.metal`, `app/Sources/Compositor.swift`,
  `CompositorEffects.swift` (the shadow encoder); chroma eyedropper
  `EditorViewController+Eyedropper.swift`.
- Nests: `core/src/nest.rs`; `EditorViewController+Nest.swift` (⌘G / ⇧⌘G).
- Reverse `ReverseRenderer.swift`; audio DSP `AudioTap.swift`, `AudioDSP.swift`; captions
  `CaptionImporter.swift`; `MediaConsolidator.swift`; `FFmpegRewrap.swift`.
- Clipboard: `EditorViewController+Clipboard.swift` over the `paste` op (`core/src/edit_paste.rs`).

## Known limits
- **Audio export is not bit-deterministic near a duck ramp edge**: two exports of one project
  differed by 38 samples of one 16-bit LSB (−90 dBFS) in an 8 ms window. AVFoundation's mix,
  inaudible. A SHA-based audio proof needs a duck-free fixture (`tools/proof/README.md` keeps it).
- **An overlap always dissolves.** `add_clip`/`move_clip` onto an overlap mint the default
  transition (`core/src/edit_transition.rs` `set_gained_transitions`), and a file's bare overlap
  renders as the default (`transition.rs` `transition_of_later`). A "no transition" baseline is
  built by separating clips.
- **Two of 2 073 600 pixels move by one LSB** when a layer has a corner radius. Deterministic
  antialiasing arithmetic; the suspected vertex-stage branch was tested and disproved.
- **A transition zone can paint over the PREVIOUS clip's selection ring** — the zone belongs to
  clip N+1 and is drawn after clip N's ring. Still one pass per clip in
  `TimelineView.swift`'s content `draw`; the fix is a two-pass loop (clips, then transitions,
  then rings) in that frozen file.
- **Noise reduction delays its track 512 samples** (10.7 ms at 48 kHz; `AudioDSP.swift`).
- Fixed since: a wrong-typed value nested in a property patch used to be silently dropped
  (orig §3.3) — road map 7's D1 hands the core the caller's raw patch; `AudioProps.mono` was
  unimplemented (orig §3.7) — road map 2's phase 5; `import_media` over MCP timed out on a first
  ffmpeg transcode, waiting 30 s on a probe the rewrap runs inside — it now waits
  `FFmpegRewrap.longestConversion` plus 300 s (`AgentServer+Media.swift` `probeCeiling`; #67,
  issue batch B1, proved by `tools/proof/export_cancel_proof.py`'s I1).

## Open items
- The person checks orig §2 lists that no later document carries — the timeline's transient
  states, the canvas overlay's unseen modes, gesture feel, the M3 inspector sections and sheets,
  and every tooltip, hover and cursor — tracked in the `ready-for-human` issues (#47–#57).
- Playback with audio, J/K/L, scrubbing and 60 fps (spec §10 steps 4–5) — tracked in #47.
- The transition zone over the previous clip's ring — tracked in #66.

## Where to look in the original
- orig §1 — M3's closing numbers (203 tests, 57 tools, format v2) and the table of what proved
  each feature.
- orig §2 — the acceptance checks that need a person, per spec §10 step.
- orig §3 — the seven known limits, with the reasoning for each.
- orig §4 — the spec §1 non-goals as they stood (partly reversed since).
- orig §5 — what "done" means.
