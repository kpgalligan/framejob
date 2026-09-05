# Reelcut — road map after M1

**Status: M1 (Cut) is built, running and verified; M2 is done but for chapter
tracks.** This is the work that is left, in the order it should be done. It is
the companion to `reelcut-design.md`, which stays normative for the schemas
(§5), the op table (§6) and the architecture (§7) — this document never
overrides it, it only says what has not been built yet and what would prove
each piece finished.

Published as a page (same content, easier to read):
<https://claude.ai/code/artifact/be6e91de-48f2-413e-a5f1-a4a91a01a0a1>

Reading order: §1 for where things stand, §2 for the two orderings that are
real, then the phase you are picking up. `CLAUDE.md` holds the current
milestone status and is the file to update as phases land.

## 1. Where things stand

`make typecheck` 0 errors · `make test` 103 passing · `make lint` clean ·
`make app` succeeded. Those four say the code builds and the core is correct.
They say nothing about whether the app is usable, which is the whole point of
Phase 1.

**Verified working**, each driven against the built binary and checked by
comparing rendered frames: opening a movie into an untitled project, import,
tracks, move / trim / split / delete / ripple, undo, transforms, crop,
markers, transitions, text and shapes, speed, freeze frame, audio levels and
ducking, `.reelcut` save and open, H.264 / HEVC / ProRes / M4A export, and the
50 MCP tools.

**Written, never seen.** The timeline view and the canvas overlay — spec §10
steps 6 and 8 — plus live playback with audio and the 60 fps target. The code
compiles and the pipeline behind it is proven, but no human has looked at
either view, and MCP cannot see the screen.

**Not built.** The shadow render pass, the chroma-key UI, the clipboard, the
`AVAssetWriter` export path and everything it unlocks, nests, filters,
reflection, spotlight, reverse, captions, noise removal, Consolidate Media,
and ffmpeg-assisted import.

## 2. The two orderings that are real

The phases are otherwise independent and can be reordered freely.

1. **Phase 1 can re-prioritise everything after it.** Two of the app's largest
   views are unexamined; what a person finds in them may outrank anything
   below.
2. **Phase 3 is one seam that three features wait on.**
   `AVAssetExportSession` cannot write a chapter track, cannot take an explicit
   bitrate, and cannot produce a GIF. All three need the `AVAssetWriter` path.

## 3. Phase 1 — Put eyes on it

**Goal:** replace "it compiles and the pipeline is proven" with "a person has
used it." No code is assumed; the likely output is a defect list.

| Work | Where | Done when |
|---|---|---|
| Timeline view | Ruler ticks at each zoom, filmstrips, waveforms, clip tints, the transition hatch, fade handles, marker flags, in/out shading — `TimelineView.swift` | Spec §10 step 6 signed off by eye; defects filed |
| Canvas overlay | Scale/rotate/move handles, crop mode and its 30 % ghost, snap guides, inline text editing — `PreviewCanvasView.swift`, `CanvasSessions.swift` | Spec §10 step 8 signed off by eye |
| Gesture feel | Drag, trim, ⌥-drag duplicate, ⌥-drag rate stretch, the animate-back on a refused drop | Each gesture is one undo step and feels right |
| Playback | Audio in sync, J/K/L, scrubbing, the 60 fps target from the compositor's own timing log | Spec §10 steps 4 and 5's human halves pass |

*Verify:* `make run`, open a movie, cut it, write down everything wrong.

## 4. Phase 2 — Make the UI's promises true

**Goal:** every control that exists does what it says. Three places where the
interface offers something the app does not deliver — worse than a missing
feature, because it is visible and silently wrong.

**Shadow is the priority.** `ShadowProps` is in the model, all three inspector
panes edit it, and it round-trips through the file — but `Compositor.metal`
has no shadow pass at all, so setting one changes nothing on screen. Found by
grepping the shader, not by using the app.

| Work | Where | Done when |
|---|---|---|
| Shadow render pass | Render the layer's alpha to an offscreen texture, blur with `MPSImageGaussianBlur`, draw it before the layer — the pass spec §7.5 describes. `Compositor.swift`'s layer loop, `Compositor.metal` | `render_frame` before and after a `set_video` with a shadow differs, and the offset matches angle and distance |
| Chroma-key UI | The shader already keys; only the inspector is missing. A Video-pane section plus a canvas eyedropper for the key colour — `VideoPane.swift`, `EditorViewController+Canvas.swift` | A green-screen clip keys from the UI alone, no MCP |
| Cut / Copy / Paste | Still disabled stubs in `plannedActions`. Clips to the pasteboard as project JSON; paste places at the playhead under the overlap rule — `EditorViewController.swift` wiring plus a new extension file | Round-trips within a document and between two open documents |

## 5. Phase 3 — The writer path

**Goal:** finish M2. The seam is documented at the top of `Exporter.swift`:
the writer path **replaces `startSession` and nothing else in that file.**

| Work | Where | Done when |
|---|---|---|
| Reader/writer pipeline | `AVAssetReader` over the same composition and video composition, feeding `AVAssetWriter` — `Exporter.swift` | Output is frame-identical to the current export path |
| Chapter track | An `AVAssetWriterInput` text track associated through `AVTrackAssociationTypeChapterList`, fed from markers whose `chapter` flag is set | `ffprobe -show_chapters` lists them — today it is empty |
| Explicit bitrates | Quality settings in the export sheet, resolved by `rc_export_settings` — `ExportSheetController.swift`, `core/src/export.rs` | Measured bitrate lands within tolerance of the requested one |
| GIF / APNG | Frame-by-frame through ImageIO, using the offline frame source `Exporter.renderFrame` already exposes | A short range exports and loops in Preview |

## 6. Phase 4 — Nests

**Goal:** ⌘G collapses a selection into one clip you can enter and edit, with
a breadcrumb back out. The one M3 feature the data model already carries:
`Source::Nest` parses and round-trips today, it simply draws nothing.

| Work | Where | Done when |
|---|---|---|
| Evaluate nests | `drawing_clips` in `core/src/evaluate.rs` filters them out today. The recipe needs a nested layer source and the plan needs the nested project's composition tracks | New core tests: a nest renders what its contents render |
| Nest / un-nest ops | `nest` and `unnest` in the §6 op table, mirrored in `ReelCore.swift` and `AgentCatalog.swift` | Nest then un-nest is the identity, like split/join |
| Enter and leave | Double-click to enter, breadcrumb in the editor chrome — `EditorViewController.swift` wiring, logic in a new extension | ⌘G / ⇧⌘G stop being disabled stubs |

## 7. Phase 5 — Effects

**Goal:** the visual polish M3 promises. Every item is a compositor pass plus
an inspector section, so the shape repeats; Phase 2's shadow pass establishes
the offscreen-texture pattern the rest reuse. Independent of each other — ship
them one at a time.

| Work | Where | Done when |
|---|---|---|
| Filters | Blur, sharpen, pixelate, sepia, noir, vignette, invert. Spec §4.3 puts Core Image behind them; a shader pass is the alternative and keeps the one-pipeline rule | Each filter changes the frame and survives save/open |
| Spotlight | Darkens the canvas outside a rectangle or ellipse with an optional 1.2–2× zoom of the region — the stand-in for a screencast editor's callout that works on any footage | Renders, and is animatable through an action |
| Reflection | A mirrored, faded copy below the layer — one more pass in the same loop | Renders at the right offset and opacity |
| Reverse | Not native to AVFoundation. §11 settles it: pre-render reversed segments into the package, then play them forward | A reversed clip plays and exports |

## 8. Phase 6 — Ingest and output

**Goal:** close out M3. Each item is self-contained; none blocks another.

| Work | Where | Done when |
|---|---|---|
| SRT captions | Import a subtitle file as text clips, and burn in on export | An SRT imports at the right times and renders |
| Audio cleanup | Remove background noise, smooth volume levels (a compressor), pan — the Audio pane's M3 section, `AudioPane.swift` | Measurable level change on a noisy sample |
| Consolidate Media | Copy referenced files into `media/` inside the package; the layout is already reserved in spec §5.6 | A consolidated project opens with its sources moved away |
| ffmpeg-assisted import | Opt-in step shelling out to a user-installed ffmpeg to rewrap MKV, WebM, VP9 and AV1 — the documented mitigation in §11 for choosing AVFoundation | An MKV opens after the rewrap, and the app degrades cleanly without ffmpeg |

## 9. Deliberately not planned

Screen and camera recording, multicam, colour grading beyond the per-clip
controls, audio beyond volume / fade / duck, a plugin system, and any platform
but macOS. These are the non-goals from spec §1 — the boundary that keeps the
app the size of a screencast editor's editor rather than Final Cut's.

## 10. What "done" means here

Verification is driving the built binary over MCP and comparing `render_frame`
output, not reading code — the launch line and the tool list are in
`CLAUDE.md`. A phase is finished when its "Done when" column is demonstrated
that way, `make test` and `make lint` are clean, and `CLAUDE.md`'s milestone
status is updated to match.
