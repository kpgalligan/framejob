# Frame Job — design and implementation spec

**The normative spec, one file per section.** It was one 4,780-line file,
`designs/reelcut-design.md`, until 2026-09-26 (git history has it). Section numbers are
unchanged, so a citation like "spec §7.3" is `07.3-frame-recipe.md` and "spec §11 W-8" is found
through [`11-decisions/README.md`](11-decisions/README.md).

**Never read the whole spec.** Read this index, then only the file for the section you need.
For a decision, look its ID up in `11-decisions/README.md`, or grep this directory
(`grep -rn "W-8 —" designs/spec/`). A file that grows past ~500 lines splits by subsection into
lettered files that keep its number (§4.3 is `04.3a`, `04.3b` and `04.3c`, §5.2 is `05.2a` and `05.2b`, §6 is `06a`, `06b` and `06c`, §7.5 is `07.5a` and `07.5b`, §7.9 is `07.9a`, `07.9b`, `07.9c` and `07.9d`);
a citation of the bare number names them together, and this index gets their rows in the same
change. Until #342 (2026-10-24) §4.3b was the Media, Document and Assistant tabs, now §4.3c; an older citation of §4.3b (in `archive/` or git history) means §4.3c.

The Lines column is `wc -l`; the `11-decisions/` cell is that folder's total, its README
included, and `make test` checks both (`tools/proof/spec_index_proof.py`).

| File | Lines | Read it for |
|---|---|---|
| [`01-what-this-is.md`](01-what-this-is.md) | 46 | The product in one page, its opening flow, and its non-goals. |
| [`02-six-ideas.md`](02-six-ideas.md) | 26 | The six ideas the model is built on, and why it stays simple. |
| [`03-window-layout.md`](03-window-layout.md) | 62 | The window's regions, as the design handoff specifies them. |
| **§4 — The regions in detail** | | |
| [`04.1-toolbar.md`](04.1-toolbar.md) | 25 | The toolbar. |
| [`04.2-preview-canvas.md`](04.2-preview-canvas.md) | 171 | The preview canvas: selection, handles, crop and region modes, on-canvas text, snapping, Show Ungraded and the scopes panel (its two slots, their sizes and the four scopes drawn). |
| [`04.3a-inspector-clip-tab.md`](04.3a-inspector-clip-tab.md) | 141 | The inspector's tab strip and its Clip tab: the sub-tabs and pinned block, the selection header and name field, sections, row marks, Reset/Clear, the note on the section list, and the controls the sections use (Rasterize's `OptionControls`). |
| [`04.3b-inspector-clip-sections.md`](04.3b-inspector-clip-sections.md) | 388 | The Clip tab's sections: every video, audio, text and shape section. |
| [`04.3c-inspector-media-document-assistant.md`](04.3c-inspector-media-document-assistant.md) | 228 | The inspector's Media tab (find band, rows, drags, Consolidate, import), the File menu's caption commands (Import, Generate and Export Captions), the Document tab and the Assistant tab. |
| [`04.4-timeline.md`](04.4-timeline.md) | 217 | The timeline: its bar, the level meter, ruler, tracks, clip bodies, gestures, entering a nest. |
| **§5 — Editing model** | | |
| [`05.1-time.md`](05.1-time.md) | 23 | Ticks (600 000 per second), frame rates, snapping to the grid. |
| [`05.2a-project-schema-canvas-media-video.md`](05.2a-project-schema-canvas-media-video.md) | 369 | The project JSON schema (format version 27): what a patch means, the example document, `source`, `canvas`, `media[]`, `graphic`, an action end's graphic and speed, `enabled`, and every `video.*` field. |
| [`05.2b-project-schema-audio-text-shape-tracks.md`](05.2b-project-schema-audio-text-shape-tracks.md) | 187 | The schema's `audio.*`, `text.*` and `shape.*` fields, `actions[].end` and `transition_in`, a clip's `name` and `label`, `tracks[].solo` and `matte`, `nests`, ids, and what is not in the model. |
| [`05.3-placement.md`](05.3-placement.md) | 81 | Where a layer lands on the canvas: position, scale, crop, regions, reflection, motion, nests flattened. |
| [`05.4-actions.md`](05.4-actions.md) | 156 | Actions (keyframed segments): what they target, how lists interpolate, a stored `null` as off. |
| [`05.5-purity-and-undo.md`](05.5-purity-and-undo.md) | 40 | An edit's three answers, purity, undo. |
| [`05.6-persistence.md`](05.6-persistence.md) | 228 | The package on disk: Consolidate, bookmarks, reversed assets, ramp audio, caches and their markers, transcripts. |
| **§6 — Edit operations: exact semantics** | | |
| [`06a-edit-operations-shared-rules.md`](06a-edit-operations-shared-rules.md) | 84 | The rules every op shares: caller ticks snapped to the frame grid, an omitted argument against `null`, how to read a "refuses", the one way a patch is read, and the `scope` envelope key (the view project, the eight ops that are an error with a scope, the checks on the merged parent). |
| [`06b-edit-operations-clips.md`](06b-edit-operations-clips.md) | 443 | Every clip op: add, insert and overwrite, the two backgrounds; move and the overlap rule; the trims, roll, slip, rate stretch, speed and reverse; split, the ripple deletes and range cuts; freeze, detach, duplicate, paste and paste attributes; nest and unnest; the patch ops; the transition ops. |
| [`06c-edit-operations-actions-tracks-media.md`](06c-edit-operations-actions-tracks-media.md) | 209 | The action ops (the zoom action, end patches and `off`); the track, marker, canvas and media ops; and the op table's two halves (the arguments half is `core/src/op_table.rs`). |
| **§7 — Architecture: Rust decides, AVFoundation and Metal do** | | |
| [`07-architecture.md`](07-architecture.md) | 25 | The Rust/platform split in one page. |
| [`07.1-ffi-surface.md`](07.1-ffi-surface.md) | 185 | The `rc_*` exports and their contracts. |
| [`07.2-composition-plan.md`](07.2-composition-plan.md) | 202 | The composition plan: A/B assignment, speed and freeze, audio envelopes, instructions. |
| [`07.3-frame-recipe.md`](07.3-frame-recipe.md) | 488 | The per-frame recipe the compositor draws: layers, mattes, nests, recipe options, burn-in, ungraded. |
| [`07.4-swift-file-map.md`](07.4-swift-file-map.md) | 58 | The spec's Swift file map (app/CLAUDE.md is the live one). |
| [`07.5a-compositor-step-0-output.md`](07.5a-compositor-step-0-output.md) | 204 | The Metal compositor's pixel formats, step 0 (per composition) and camera log, the request and the scopes' tap (the shown set, the kernels, the counting rule), the HLG working space, the output pass and linear light. |
| [`07.5b-compositor-passes-grades.md`](07.5b-compositor-passes-grades.md) | 326 | The compositor's per-layer passes and pipelines, the adjustment pass and its qualifier, the encoded-sRGB blend, transitions, mattes, tone, wheels, curves, looks and `.cube` LUTs, and the frame budget. |
| [`07.6-playback-update-rules.md`](07.6-playback-update-rules.md) | 46 | What playback does after every edit: rebuild or refresh. |
| [`07.7-import.md`](07.7-import.md) | 233 | `MediaImporter.probe`, the formats import accepts, the WebM/Matroska rewrap and its PQ copy's HDR10 fields, its copy's progress window, the copy's original, and the opt-in ffmpeg step's original and checked VP9 copy. |
| [`07.8-export.md`](07.8-export.md) | 560 | Export: writers, formats, loudness, the queue, the wait for ramp audio. |
| [`07.9a-agent-tools.md`](07.9a-agent-tools.md) | 479 | The MCP agent's tools: one tool per op plus `scope`, the parity check and the argument gate, the app-state tools, lenient decoding. |
| [`07.9b-agent-lane-assistant.md`](07.9b-agent-lane-assistant.md) | 160 | The agent lane every tool call goes through, the bundled helper, the assistant session (its key, prices and spend), its prompt, and the Assistant tab as the session's door. |
| [`07.9c-agent-graphics-dev-tools-transport.md`](07.9c-agent-graphics-dev-tools-transport.md) | 312 | The graphics loop's tools (write, read, render, import, delete, rename and restore a module), an action's graphic props and the graphics menus, the dev tools (`snapshot_ui`, `perform_menu_item`, `cancel_sheet`, `select_inspector_tab`, `assistant_send` / `assistant_answer` and their launch defaults, `play_preview`, `graphic_memory`), and the transport (the Unix socket, `framejob-mcp`, Copy MCP Command). |
| [`07.9d-agent-recording.md`](07.9d-agent-recording.md) | 46 | `record_screen`, File ▸ New Recording…'s mirror: its arguments, the grants it reads and never asks, its refusal order, a paused recording's segments, the voice-over, a camera alone and a camera beside the screen, and its answer. |
| [`07.10-rust-module-map.md`](07.10-rust-module-map.md) | 110 | The spec's Rust module map (core/CLAUDE.md is the live one). |
| [`08-repo-layout.md`](08-repo-layout.md) | 66 | Repo layout, build, conventions. |
| [`09-keys-and-menus.md`](09-keys-and-menus.md) | 197 | The keyboard map and every menu, and keys proposed but not yet bound. |
| [`10-milestones.md`](10-milestones.md) | 70 | M1–M3 in build order; each step's *Verify* is an acceptance test. |
| [`11-decisions/`](11-decisions/README.md) | 14118 in 33 files | Every decision already made, indexed by ID. |

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

