# Frame Job — design and implementation spec

**The normative spec, one file per section.** It was one 4,780-line file,
`designs/reelcut-design.md`, until 2026-09-26 (git history has it). Section numbers are
unchanged, so a citation like "spec §7.3" is `07.3-frame-recipe.md` and "spec §11 W-8" is found
through [`11-decisions/README.md`](11-decisions/README.md).

**Never read the whole spec.** Read this index, then only the file for the section you need.
For a decision, look its ID up in `11-decisions/README.md`, or grep this directory
(`grep -rn "W-8 —" designs/spec/`). A file that grows past ~500 lines splits by subsection into
lettered files that keep its number (§4.3 is `04.3a`, `04.3b`, `04.3c`, `04.3d` and `04.3e`, §5.2 is `05.2a` and `05.2b`, §6 is `06a`, `06b`, `06c` and `06d`, §7.5 is `07.5a` and `07.5b`, §7.3 is `07.3` and `07.3b`, §7.8 is `07.8`, `07.8b` and `07.8c`, §7.9 is `07.9a`, `07.9b`, `07.9c`, `07.9d`, `07.9e`, `07.9f`, `07.9g`, `07.9h`, `07.9i` and `07.9j`);
a citation of the bare number names them together, and this index gets their rows in the same
change. An index is exempt: this file and `11-decisions/README.md`, which grows a row per decision. A §11 file splits at an entry or phase boundary into `<name>-2.md`, `-3.md` …, or into a lettered `<name>b.md` where the next number is taken (`creator-jobs-9b.md`; `creator-jobs-1b.md` continues `creator-jobs.md`), and a citation of the bare name names them together. Until #342 (2026-10-24) §4.3b was the Media, Document and Assistant tabs, now §4.3c; an older citation of §4.3b (in `archive/` or git history) means §4.3c.

The Lines column is `wc -l`; the `11-decisions/` cell is that folder's total, its README
included, and `make test` checks both (`tools/proof/spec_index_proof.py`).

| File | Lines | Read it for |
|---|---|---|
| [`01-what-this-is.md`](01-what-this-is.md) | 34 | The product in one page, its opening flow, and the scope it no longer limits (§11 CJ-1). |
| [`02-six-ideas.md`](02-six-ideas.md) | 28 | The six ideas the model is built on, and why it stays simple. |
| [`03-window-layout.md`](03-window-layout.md) | 73 | The window's regions, as the design handoff specifies them. |
| **§4 — The regions in detail** | | |
| [`04.1-toolbar.md`](04.1-toolbar.md) | 25 | The toolbar. |
| [`04.2-preview-canvas.md`](04.2-preview-canvas.md) | 201 | The preview canvas: selection, handles, crop and region modes, on-canvas text, snapping, Show Ungraded and the scopes panel (its two slots, their sizes and the four scopes drawn). |
| [`04.3a-inspector-clip-tab.md`](04.3a-inspector-clip-tab.md) | 146 | The inspector's tab strip and its Clip tab: the sub-tabs and pinned block, the selection header and name field, sections, row marks, Reset/Clear, the note on the section list, and the controls the sections use (Rasterize's `OptionControls`). |
| [`04.3b-inspector-clip-sections.md`](04.3b-inspector-clip-sections.md) | 364 | The Clip tab's sections: every video section. |
| [`04.3c-inspector-media-document-assistant.md`](04.3c-inspector-media-document-assistant.md) | 250 | The inspector's Media tab (find band, rows, drags, Consolidate, import), the File menu's caption commands (Import, Generate and Export Captions), the Document tab and the Assistant tab. |
| [`04.3d-inspector-clip-sections-audio-text-shape.md`](04.3d-inspector-clip-sections-audio-text-shape.md) | 247 | The Clip tab's audio, text and shape sections (continues §4.3b). |
| [`04.3e-inspector-transcript-tab.md`](04.3e-inspector-transcript-tab.md) | 173 | The inspector's Transcript tab (road map "creator-jobs" TX2a, TX2b, TX3a, TX1b, TX3b): the timeline's words in paragraphs, the bar (Words from, Language, the status with Stop or Read, the notes), the highlight that follows the playhead, a click to seek, the keys, selecting words as the in/out range and deleting them as one "Delete Words" (where a cut falls, the refusals), pause tokens shortened as one "Delete Pause", the reading on this Mac and the rebuilds. |
| [`04.4-timeline.md`](04.4-timeline.md) | 283 | The timeline: its bar, the level meter, ruler, tracks, clip bodies, gestures, entering a nest. |
| **§5 — Editing model** | | |
| [`05.1-time.md`](05.1-time.md) | 32 | Ticks (600 000 per second), frame rates, snapping to the grid, frames timecode. |
| [`05.2a-project-schema-canvas-media-video.md`](05.2a-project-schema-canvas-media-video.md) | 469 | The project JSON schema (format version 34): what a patch means, the example document, `source`, `canvas`, `media[]`, `graphic`, an action end's graphic and speed, `enabled`, and every `video.*` field. |
| [`05.2b-project-schema-audio-text-shape-tracks.md`](05.2b-project-schema-audio-text-shape-tracks.md) | 317 | The schema's `audio.*`, `text.*` and `shape.*` fields, `actions[].end` and `transition_in`, a clip's `name` and `label`, `tracks[].solo` and `matte`, `nests`, ids, and what is not in the model. |
| [`05.3-placement.md`](05.3-placement.md) | 81 | Where a layer lands on the canvas: position, scale, crop, regions, reflection, motion, nests flattened. |
| [`05.4-actions.md`](05.4-actions.md) | 198 | Actions (keyframed segments): what they target, how lists interpolate, a stored `null` as off. |
| [`05.5-purity-and-undo.md`](05.5-purity-and-undo.md) | 40 | An edit's three answers, purity, undo. |
| [`05.6-persistence.md`](05.6-persistence.md) | 374 | The package on disk: Consolidate, bookmarks, reversed assets, ramp audio, isolated voice, voiced sound, caches and their markers, transcripts, the analysis cache. |
| **§6 — Edit operations: exact semantics** | | |
| [`06a-edit-operations-shared-rules.md`](06a-edit-operations-shared-rules.md) | 110 | The rules every op shares: caller ticks snapped to the frame grid, an omitted argument against `null`, a linked pair moving as one in time (format 28, AU-90…AU-96), how to read a "refuses", the one way a patch is read, and the `scope` envelope key (the view project, the eleven ops that are an error with a scope, the checks on the merged parent). |
| [`06b-edit-operations-clips.md`](06b-edit-operations-clips.md) | 515 | Every clip op: add, insert and overwrite, the two backgrounds; move and the overlap rule; the trims, roll, slip, rate stretch, speed and reverse; split, the ripple deletes and range cuts; freeze, detach, duplicate, `copy_pieces`, paste and paste attributes; nest and unnest; the patch ops; `retime_range`. The transition ops are §6d. |
| [`06d-edit-operations-transitions.md`](06d-edit-operations-transitions.md) | 69 | The transition ops, continuing §6b: `set_transition`, `set_transition_duration`, `add_transition` (handles and the ripple form) and `set_transition_style`. |
| [`06c-edit-operations-actions-tracks-media.md`](06c-edit-operations-actions-tracks-media.md) | 443 | The action ops (the zoom action, the camera layout switch, end patches and `off`); the track, marker, canvas and media ops; and the op table's two halves (the arguments half is `core/src/op_table.rs`). |
| **§7 — Architecture: Rust decides, AVFoundation and Metal do** | | |
| [`07-architecture.md`](07-architecture.md) | 25 | The Rust/platform split in one page. |
| [`07.1-ffi-surface.md`](07.1-ffi-surface.md) | 227 | The `rc_*` exports and their contracts. |
| [`07.2-composition-plan.md`](07.2-composition-plan.md) | 338 | The composition plan: A/B assignment, speed and freeze, audio envelopes, the tap's isolation and voice pass, instructions. |
| [`07.3-frame-recipe.md`](07.3-frame-recipe.md) | 468 | The per-frame recipe the compositor draws: layers, mattes, nests, the cursor, cutout and blur keys. |
| [`07.3b-frame-recipe-options.md`](07.3b-frame-recipe-options.md) | 108 | §7.3 continued: the recipe options — burn-in, ungraded, selection and behind, the SDR version — and how an option reaches a frame. |
| [`07.4-swift-file-map.md`](07.4-swift-file-map.md) | 109 | The spec's Swift file map (app/CLAUDE.md is the live one). |
| [`07.5a-compositor-step-0-output.md`](07.5a-compositor-step-0-output.md) | 204 | The Metal compositor's pixel formats, step 0 (per composition) and camera log, the request and the scopes' tap (the shown set, the kernels, the counting rule), the HLG working space, the output pass and linear light. |
| [`07.5b-compositor-passes-grades.md`](07.5b-compositor-passes-grades.md) | 434 | The compositor's per-layer passes and pipelines, the cursor and the cutout, the adjustment pass and its qualifier, the encoded-sRGB blend, transitions, mattes, tone, wheels, curves, looks and `.cube` LUTs, and the frame budget. |
| [`07.6-playback-update-rules.md`](07.6-playback-update-rules.md) | 70 | What playback does after every edit: rebuild or refresh. |
| [`07.7-import.md`](07.7-import.md) | 275 | `MediaImporter.probe`, the formats import accepts, the cursor file attached at import and relink, the WebM/Matroska rewrap and its PQ copy's HDR10 fields, its copy's progress window, the copy's original, and the opt-in ffmpeg step's original and checked VP9 copy. |
| [`07.8-export.md`](07.8-export.md) | 342 | Export: the presets and settings, writers, formats, Quality, each codec's row (ProRes 4444, HEVC with alpha and 10-bit, AV1, AV1 and VP9 in WebM, VP9 alpha), and the queue's encoder memory and time estimate. |
| [`07.8b-export-picture-and-refusals.md`](07.8b-export-picture-and-refusals.md) | 150 | §7.8 continued: depth, an HLG project, the deliverables, a frame within a pixel of the canvas's shape, and what can only stop an export. |
| [`07.8c-export-sound-waits-gif-graphics.md`](07.8c-export-sound-waits-gif-graphics.md) | 321 | §7.8 continued: WAV and AIFF, stems, track and bus dynamics, loudness, the master, where a sample lands, the wait for person masks, ramp audio, isolated voice and voice effects, GIF and APNG, graphics. |
| [`07.9a-agent-tools.md`](07.9a-agent-tools.md) | 133 | The MCP agent's tools: one tool per op plus `scope`, the parity check and the argument gate, lenient decoding (`set_media_color`, `set_media_speech` and `set_audio`'s `duck.mode` are in §7.9e). |
| [`07.9b-agent-lane-assistant.md`](07.9b-agent-lane-assistant.md) | 185 | The agent lane every tool call goes through, the bundled helper, the assistant session (its key, prices and spend), its prompt, and the Assistant tab as the session's door. |
| [`07.9c-agent-graphics-dev-tools-transport.md`](07.9c-agent-graphics-dev-tools-transport.md) | 558 | The graphics loop's tools (write, read, render, import, delete, rename and restore a module, list, insert and export from the graphic browser, import a `.fjgraphic`), an action's graphic props and the graphics menus, the dev tools (`snapshot_ui`, `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`, `assistant_send` / `assistant_answer` and their launch defaults, `play_preview`, `graphic_memory`, `loudness_meter`, `land_recording`, `analysis_job` and the analysis launch defaults, `cache_ledger`, `transcript_view`, `playback_rebuilds` and `-RCDevRebuildHold`), and the transport (the Unix socket, `framejob-mcp`, Copy MCP Command). |
| [`07.9d-agent-recording.md`](07.9d-agent-recording.md) | 226 | `record_screen`, File ▸ New Recording…'s mirror: its arguments, the grants it reads and never asks, its refusal order, a paused recording's segments, the voice-over, a camera alone and a camera beside the screen, `enhance` (Enhance Voice after the landing), each segment's cursor file, and its answer; and a recording's cursor file after it lands: `set_media_cursor` and `get_cursor_events` (§11 CU-50, CU-53); and `auto_zoom` (§11 CU-76), `add_shortcut_overlays` (§11 CU-84) and `speed_up_typing` (§11 CU-93). |
| [`07.9e-agent-app-state-tools.md`](07.9e-agent-app-state-tools.md) | 505 | The app-state tools (the tools that are not ops): scope, documents, media, captions, transcripts, detection, Normalize, Enhance, Match, Synchronize, `render_frame` and export; and the op tools `set_media_color` and `set_media_speech`, and `set_audio`'s `duck.mode`. |
| [`07.9f-agent-transcript.md`](07.9f-agent-transcript.md) | 105 | The timeline transcript, `get_timeline_transcript`: what is read (the plan's audio segments, nested ones with `path` and `origin`), on-device starts moved to their sound (TX1b), the answer (words with clip, track, editability, identity and the tab's `cut_start`/`cut_end`; `pauses` with their cuts; `media`, `no_words`, `notes`), the window and `tracks`, paging at 2,000 words, and the whole-file fill (§11 TX-10…TX-18, TX-30, TX-33, TX-34). |
| [`07.9g-agent-behind-subject.md`](07.9g-agent-behind-subject.md) | 39 | Text Behind Subject's tool, `text_behind_subject`: the planner it runs (the pick, the new track above the mattes, the title, the cutout that keeps the background), its answer and its refusals (§11 CO-53, CO-54). |
| [`07.9h-agent-switch.md`](07.9h-agent-switch.md) | 118 | `copy_pieces`'s tool and Switch Angle's, `switch_angle`: the empty-list refusal, covering, the re-pick's sequence tried one op at a time, the held edge, the answer and the refusals (§11 SW-11…SW-15); `switch_by_speaker`: its arguments, ranges and defaults, errors, refusals, the ops and the answer (§11 SW-23, SW-26); its faces mode, off-main wait and `mode`/`note` (§11 SW-80…SW-86). |
| [`07.9i-agent-vertical.md`](07.9i-agent-vertical.md) | 182 | `make_vertical_version`: its arguments, the size, the step's classes and order, a canvas-size graphic re-sized, the caption step (6), the treatments and reasons, the copy and its old template copies updated (§11 VR-42, VR-44), the analysis on the source, the answer and the refusals in order; ask-first only with `path` (§11 VR-30…VR-37); `relay_captions`: the survey, the re-lay, its answer and refusal (§11 VR-40, VR-45). |
| [`07.9j-agent-analysis-tools.md`](07.9j-agent-analysis-tools.md) | 117 | The media analysis tools, §7.9e's until #448: `get_media_analysis` (every kind: shots, masks, faces, sound_events, subjects, and its refusals), Split at Shot Changes (`split_at_shots`) and `analyze_cutout`. |
| [`07.10-rust-module-map.md`](07.10-rust-module-map.md) | 161 | The spec's Rust module map (core/CLAUDE.md is the live one). |
| [`08-repo-layout.md`](08-repo-layout.md) | 66 | Repo layout, build, conventions. |
| [`09-keys-and-menus.md`](09-keys-and-menus.md) | 335 | The keyboard map and every menu, and keys proposed but not yet bound. |
| [`10-milestones.md`](10-milestones.md) | 70 | M1–M3 in build order; each step's *Verify* is an acceptance test. |
| [`11-decisions/`](11-decisions/README.md) | 25708 in 66 files | Every decision already made, indexed by ID. |

## The original preface

**Status: accepted and built** (M1–M3, then road maps 2–12; `designs/adr/` has each one's
record). The preface below is the original handoff's, kept for its reading order.

Sibling of `~/devel/rasterize` — the same shape (Swift/AppKit app over a Rust staticlib core, a
hand-maintained C header as the one contract, xcodegen, an embedded MCP agent), a different domain.
Where this document says "as in Rasterize" it names the file to copy from.

Reading order for an implementer: §1–2 (the product), §5–7 (model, ops,
architecture — the parts with exact schemas), §10 (build order), then §3–4
when building the UI, §8–9 for conventions and keys, §11 for the decisions
already made so they are not re-litigated.

