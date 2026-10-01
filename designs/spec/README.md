# Reelcut — design and implementation spec

**The normative spec, one file per section.** It was one 4,780-line file,
`designs/reelcut-design.md`, until 2026-09-26 (git history has it). Section numbers are
unchanged, so a citation like "spec §7.3" is `07.3-frame-recipe.md` and "spec §11 W-8" is found
through [`11-decisions/README.md`](11-decisions/README.md).

**Never read the whole spec.** Read this index, then only the file for the section you need.
For a decision, look its ID up in `11-decisions/README.md`, or grep this directory
(`grep -rn "W-8 —" designs/spec/`). A file that grows past ~500 lines splits by subsection into
lettered files that keep its number (§4.3 is `04.3a` and `04.3b`, §6 is `06a`, `06b` and `06c`, §7.9 is `07.9a` and `07.9b`);
a citation of the bare number names them together, and this index gets their rows in the same
change.

| File | Lines | Read it for |
|---|---|---|
| [`01-what-this-is.md`](01-what-this-is.md) | 32 | The product in one page, its opening flow, and its non-goals. |
| [`02-six-ideas.md`](02-six-ideas.md) | 26 | The six a screencast editor ideas the model copies, and why it stays simple. |
| [`03-window-layout.md`](03-window-layout.md) | 62 | The window's regions, as the design handoff specifies them. |
| **§4 — The regions in detail** | | |
| [`04.1-toolbar.md`](04.1-toolbar.md) | 26 | The toolbar. |
| [`04.2-preview-canvas.md`](04.2-preview-canvas.md) | 72 | The preview canvas: selection, handles, crop and region modes, on-canvas text, snapping. |
| [`04.3a-inspector-clip-tab.md`](04.3a-inspector-clip-tab.md) | 348 | The inspector's tab strip and its Clip tab: the sub-tabs and pinned block, the selection header and name field, sections, row marks, Reset/Clear; every video, audio, text and shape section. |
| [`04.3b-inspector-media-document-assistant.md`](04.3b-inspector-media-document-assistant.md) | 157 | The inspector's Media tab (find band, rows, drags, Consolidate, import, generate and export captions), Document tab and Assistant tab. |
| [`04.4-timeline.md`](04.4-timeline.md) | 193 | The timeline: its bar, the level meter, ruler, tracks, clip bodies, gestures, entering a nest. |
| **§5 — Editing model** | | |
| [`05.1-time.md`](05.1-time.md) | 23 | Ticks (600 000 per second), frame rates, snapping to the grid. |
| [`05.2-project-schema.md`](05.2-project-schema.md) | 355 | The project JSON schema: every persisted field (format version 10). |
| [`05.3-placement.md`](05.3-placement.md) | 81 | Where a layer lands on the canvas: position, scale, crop, regions, reflection, motion, nests flattened. |
| [`05.4-actions.md`](05.4-actions.md) | 81 | Actions (keyframed segments): what they target, how lists interpolate, a stored `null` as off. |
| [`05.5-purity-and-undo.md`](05.5-purity-and-undo.md) | 40 | An edit's three answers, purity, undo. |
| [`05.6-persistence.md`](05.6-persistence.md) | 147 | The package on disk: Consolidate, bookmarks, reversed assets, caches and their markers, transcripts. |
| **§6 — Edit operations: exact semantics** | | |
| [`06a-edit-operations-shared-rules.md`](06a-edit-operations-shared-rules.md) | 82 | The rules every op shares: caller ticks snapped to the frame grid, an omitted argument against `null`, how to read a "refuses", the one way a patch is read, and the `scope` envelope key (the view project, the seven ops that are an error with a scope, the checks on the merged parent). |
| [`06b-edit-operations-clips.md`](06b-edit-operations-clips.md) | 342 | Every clip op: add, insert and overwrite, the two backgrounds; move and the overlap rule; the trims, roll, slip, rate stretch, speed and reverse; split, the ripple deletes and range cuts; freeze, detach, duplicate, paste and paste attributes; nest and unnest; the patch ops; the transition ops. |
| [`06c-edit-operations-actions-tracks-media.md`](06c-edit-operations-actions-tracks-media.md) | 92 | The action ops (the zoom action, end patches and `off`); the track, marker, canvas and media ops; and the op table's two halves (the arguments half is `core/src/op_table.rs`). |
| **§7 — Architecture: Rust decides, AVFoundation and Metal do** | | |
| [`07-architecture.md`](07-architecture.md) | 25 | The Rust/platform split in one page. |
| [`07.1-ffi-surface.md`](07.1-ffi-surface.md) | 116 | The `rc_*` exports and their contracts. |
| [`07.2-composition-plan.md`](07.2-composition-plan.md) | 114 | The composition plan: A/B assignment, speed and freeze, audio envelopes, instructions. |
| [`07.3-frame-recipe.md`](07.3-frame-recipe.md) | 267 | The per-frame recipe the compositor draws: layers, nests, recipe options, burn-in. |
| [`07.4-swift-file-map.md`](07.4-swift-file-map.md) | 41 | The spec's Swift file map (app/CLAUDE.md is the live one). |
| [`07.5-compositor.md`](07.5-compositor.md) | 106 | The Metal compositor's passes, and transitions. |
| [`07.6-playback-update-rules.md`](07.6-playback-update-rules.md) | 42 | What playback does after every edit: rebuild or refresh. |
| [`07.7-import.md`](07.7-import.md) | 20 | `MediaImporter.probe` and the formats import accepts. |
| [`07.8-export.md`](07.8-export.md) | 235 | Export: writers, formats, loudness, the queue. |
| [`07.9a-agent-tools.md`](07.9a-agent-tools.md) | 379 | The MCP agent's tools: one tool per op plus `scope`, the parity check and the argument gate, the app-state tools, lenient decoding, the graphics loop, the dev tools, the port. |
| [`07.9b-agent-lane-assistant.md`](07.9b-agent-lane-assistant.md) | 154 | The agent lane every tool call goes through, the bundled helper, the assistant session (its key, prices and spend), its prompt, and the Assistant tab as the session's door. |
| [`07.10-rust-module-map.md`](07.10-rust-module-map.md) | 76 | The spec's Rust module map (core/CLAUDE.md is the live one). |
| [`08-repo-layout.md`](08-repo-layout.md) | 64 | Repo layout, build, conventions. |
| [`09-keys-and-menus.md`](09-keys-and-menus.md) | 138 | The keyboard map and every menu, and keys proposed but not yet bound. |
| [`10-milestones.md`](10-milestones.md) | 70 | M1–M3 in build order; each step's *Verify* is an acceptance test. |
| [`11-decisions/`](11-decisions/README.md) | 2411 in 13 files | Every decision already made, indexed by ID. |

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

