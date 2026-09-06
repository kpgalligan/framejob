# Reelcut — road map after M1

**Status: M1, M2 and M3 are built. Every feature in `reelcut-design.md`'s
milestone list (§10) is implemented and verified against a running binary.**
What is left is not features: it is the half of the acceptance tests that
needs a person at the machine, and a short list of known limits.

This is the companion to `reelcut-design.md`, which stays normative for the
schemas (§5), the op table (§6) and the architecture (§7); this document never
overrides it. `CLAUDE.md` holds the milestone status and is the file to update
as work lands.

Published as a page (the pre-M3 version, kept for the phase plan it describes):
<https://claude.ai/code/artifact/be6e91de-48f2-413e-a5f1-a4a91a01a0a1>

## 1. Where things stand

`make test` 203 passing · `make lint` clean · `make typecheck` 0 errors,
4 warnings (AVFoundation deprecations, deliberate) · `make app` succeeded ·
57 MCP tools · format version 2.

**Verified by driving the built binary and comparing rendered frames or
measured audio** — the standard this project holds itself to, and the reason
each line below is a claim rather than a hope:

| Landed | What proved it |
|---|---|
| Shadow render pass | Offset measured at exactly `distance × scale` along the angle; occluded by its own layer |
| Chroma-key UI + canvas eyedropper | A green-screen clip keys from the UI alone |
| Cut / Copy / Paste (`paste` op) | Round-trips within and between documents; one undo step |
| `AVAssetWriter` export path | Replaced `AVAssetExportSession` outright; frame-identical output |
| Chapter tracks | `ffprobe -show_chapters` lists them in mp4, mov and m4a — the test M2 owed from the start |
| Explicit bitrates | Measured within 3–7 % of the request on a pathological source |
| GIF / APNG | Byte-level parse: image descriptors, per-frame delays, NETSCAPE loop |
| Filters (7 kinds) | Each changes the frame; an empty list is byte-identical to none; order matters |
| Spotlight | Outside dimmed to exactly `1 − dim`; the zoom is a real magnification, not a redraw |
| Reflection | Per-row least squares fits the mirrored source, 47/47 rows |
| Nests (`nest` / `unnest`) | A nest renders byte-identically to its contents; unnest is the identity |
| Nested audio | Nested ducking and mute match the top-level result to the decibel |
| Reverse | Frame order swaps; correct inside a nest and through export |
| Audio pan / compressor / noise reduction | Each measurably changes the export; neutral settings are bit-identical |
| SRT captions | Cues land at the right times and render |
| Consolidate Media | Reopens after the originals are deleted and the package moved |
| ffmpeg-assisted import | An MKV opens after rewrap; degrades cleanly with no ffmpeg |

## 2. What still needs a person at the machine

MCP cannot see the screen or hear the audio, so these are unverified — not
unbuilt. This is the whole of what is left of the acceptance tests.

| Work | Spec | Why an agent cannot close it |
|---|---|---|
| Timeline view | §10 step 6 | Ruler ticks at each zoom, filmstrips, waveforms, tints, the transition hatch, fade handles, marker flags, in/out shading. Screenshots show it draws and draws the right things; whether it *reads* well is a judgement |
| Canvas overlay | §10 step 8 | Scale / rotate / move handles, crop mode and its 30 % ghost, snap guides, inline text editing |
| Gesture feel | §4.4 | Drag, trim, ⌥-drag duplicate, ⌥-drag rate stretch, the animate-back on a refused drop. Each is one undo step; whether each *feels* right is not measurable |
| Playback | §10 steps 4–5 | Audio in sync, J/K/L, scrubbing, and the 60 fps target from the compositor's own timing log |
| The new UI | — | ⌘G / ⇧⌘G, the reverse progress sheet's Cancel and failure paths, the export sheet's Quality row, and the Filters / Spotlight / Reflection / Audio-cleanup sections |

## 3. Known limits, deliberate or deferred

1. **You cannot edit inside a nest.** Every op's `clip` argument resolves
   through `Project::clip`, which does not see nested clips. The round trip
   (⇧⌘G, edit, ⌘G) is the way in. Entering a nest with a breadcrumb is
   designed (spec §4.4) and not built.
2. **Audio export is not bit-deterministic near a duck ramp edge** — two
   exports of one unchanged project differed by 38 samples of one 16-bit LSB
   (−90 dBFS) in an 8 ms window. AVFoundation's mix, pre-existing, inaudible;
   it means SHA-based audio comparisons need a fixture without a duck edge.
3. **A wrong-typed value nested inside a property patch is still dropped.**
   `set_video {patch: {shadow: {distance: "far"}}}` silently creates a default
   shadow. The top-level round-trip check cannot recurse safely, because a
   field legitimately set *to* its default is indistinguishable from absence.
   This wants a real schema, not a deeper oracle; documented in place on
   `patchArg`.
4. **`add_clip` onto an overlap assigns the default `cross_dissolve`**, and an
   overlap with no kind still dissolves. A "no transition" baseline has to be
   built by separating clips, not by clearing the kind.
5. **Two pixels of 2 073 600 move by one LSB** when a layer has a corner
   radius. Deterministic, so real; antialiasing arithmetic, not behaviour. The
   suspected cause (a branch in the vertex stage) was tested and disproved.
6. `AudioProps.mono` is in the schema and unimplemented. Noise reduction
   delays its track 512 samples. `import_media` over MCP can time out on a
   first ffmpeg transcode, though the conversion completes and a second call
   is instant.

## 4. Deliberately not planned

Screen and camera recording, multicam, colour grading beyond the per-clip
controls, audio beyond volume / fade / duck / pan / compression / noise
reduction, a plugin system, and any platform but macOS. These are the
non-goals from spec §1 — the boundary that keeps the app the size of
a screencast editor's editor rather than Final Cut's.

## 5. What "done" means here

Verification is driving the built binary over MCP and comparing `render_frame`
output or measured audio, not reading code — the launch line and the tool list
are in `CLAUDE.md`. Work is finished when that evidence exists, `make test`
and `make lint` are clean, and `CLAUDE.md`'s milestone status matches.
