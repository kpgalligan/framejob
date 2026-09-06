# CLAUDE.md

Reelcut — a screencast-style video editor for macOS: a Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`.

**It builds and runs.** M1 (Cut) is done and verified against spec §10; most
of M2 landed with it.

Two documents in `designs/`, and you want both:

- `designs/reelcut-design.md` — the normative spec. The schemas (§5), the op
  table (§6) and the architecture (§7) govern any change to either side; §11
  holds decisions already made, which are not to be re-litigated.
- **`designs/reelcut-roadmap.md` — what is left to build, in six phases**,
  each naming the files it lands in and what would prove it done. **Start
  here if you are picking up new work.** Phase 1 is "put eyes on the app":
  the timeline view and canvas overlay have never been looked at by a person,
  and what that turns up may re-order everything after it.

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release  (222 black-box tests)
make lint       # cargo clippy --all-targets -- -D warnings
make typecheck  # swiftc -typecheck of app/Sources/*.swift — the ONLY authoritative Swift check
make project    # xcodegen generate (Reelcut.xcodeproj is generated; project.yml is the source of truth)
make run        # make app, then launch
```

`make typecheck` is fast and catches nearly everything; run it before
`make app` (~90 s). Rust changes need `make test` and `make lint` too.
`make typecheck` currently reports 0 errors and 4 warnings, all AVFoundation
deprecations (3 in `CompositionBuilder.swift`, 1 in `Exporter.swift`), which
are deliberate — their replacements are `async`-only and `async` is confined
to `MediaImporter.swift`. That is the whole baseline; any fifth warning is
new and yours.

## File map

```
core/                Rust staticlib — the model, the ops, the plan, the recipe,
  include/…_core.h     export settings, the generic MCP server. THE FFI CONTRACT
  src/                 model time edit(+_clip/_props/_track/_time) actions
                       transition evaluate audio snap format export agent ffi*
  tests/               black-box, through the FFI (core/CLAUDE.md)
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass
  Bridging/            the bridging header importing core/include/reelcut_core.h
designs/             reelcut-design.md — normative spec
project.yml          xcodegen definition; Makefile; README.md (user-facing)
```

Per-side detail lives in `core/CLAUDE.md` and `app/CLAUDE.md`. Read the one
for the side you are editing before writing code; do not duplicate it here.

## Rules

- Conventions are Rasterize's — `~/devel/rasterize`'s three `CLAUDE.md`
  files are the parent text for anything not settled here.
- **Rust decides, AVFoundation and Metal do** (spec §7). No pixel or sample
  work in Rust; no ffmpeg dependency in the product.
- **The FFI is three files in lockstep**: a Rust `#[no_mangle]` export, its
  entry in `core/include/reelcut_core.h`, and its wrapper in
  `app/Sources/ReelCore.swift`. Persisted-state changes bump
  `RC_FORMAT_VERSION` in both `core/src/format.rs` and the header.
- **`app/Sources/ReelCore.swift` is the only file that calls `rc_*`.** Edits
  are JSON ops through `rc_project_apply`. The op table is the module doc of
  `core/src/edit.rs`; `ReelCore.swift`'s typed builders and
  `AgentCatalog.swift`'s tools both mirror it, and spec §6 mirrors it again —
  change one, change all four.
- **Every edit is pure and returns `Option`** (identity or a documented
  refusal = `None`, no undo step). `ProjectDocument` is the single mutation
  point and undo is its stack of handles.
- **Every user-visible edit gets an MCP mirror** (spec §7.9): a handler, a
  catalog entry, and a comment naming the UI path. The startup parity check
  in `AgentServer.start()` enforces catalog names against handler names,
  every op in the core's table against the tools (read through `rc_op_names`,
  with an explicit allow-list for ops that deliberately have none), and each
  tool's schema shape. It cannot see argument TYPES — the throwing helpers in
  `AgentServer+Arguments.swift` are the guard for those, `patchArg` included:
  a value a patch could not read is refused by name, never dropped.

## Verifying a build

The app is verified by driving the built binary over MCP and comparing
`render_frame` output — not by reading code. Launch your own instance on your
own port and only ever kill that one (`pgrep -f "MacOS/Reelcut"` lists them;
another session may have one running):

```sh
make app
(RC_AGENT_PORT=4817 ./build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES -AgentServerEnabled YES > /tmp/reelcut-4817.log 2>&1 &)
```

The log line names the port it actually bound (a taken port falls back to an
ephemeral one). Then drive it with any MCP client over streamable HTTP at
`http://127.0.0.1:<port>/mcp` — 57 tools: one per §6 op (43) plus `open_project`,
`new_project`, `save_project`, `get_project`, `import_media`, `import_captions`,
`consolidate_media`, `set_playhead`, `set_range`, `set_selection`, `undo`, `redo`,
`render_frame` and `export`.
`render_frame` writes a PNG and returns its path, so a script can diff it
against `ffmpeg`-extracted source frames; `export` waits for the file.

Spec §10's per-step verifications are the acceptance tests. Steps 3, 4, 5, 7,
9, 10, 11 and 12 have been run against a built app and passed; 1 and 2 are
what `make app` and `make test` check every time. **Steps 6 (timeline view)
and 8 (canvas overlay) are visual and have never been checked by anyone**, and
neither has step 4's "the clip plays with audio" or step 5's 60 fps — MCP
cannot see the screen. Those need eyes on the app.

## Milestone status

- **M1 — Cut: done.** Open a movie into an untitled project at its size and
  rate, import, tracks, move/trim/split/delete/ripple, playback and JKL,
  transform/crop/opacity, markers, `.reelcut` save/open, undo, H.264 and HEVC
  export (⌘E's Format popup opens on `h264`, the first row of `export.rs`'s
  encoding-only table, and its Size popup on the first row of
  `rc_export_sizes` — the document's own size — so an export is at the
  document's size unless another row or a custom size is picked), and
  cut/copy/paste (⌘X/⌘C/⌘V — `EditorViewController+Clipboard.swift`
  over the `paste` op, whose payload schema is `core/src/edit_paste.rs`'s
  module doc).
- **M2 — Compose: done.** Text, shapes, transitions, audio
  volume/fade/duck/detach, freeze frame, speed, in/out range, and the MCP
  agent all work through the ops, the inspector, and the Add Text / Add Shape
  toolbar buttons (`EditorViewController+AddClips.swift`, which places on the
  front track and falls back to a new one when the overlap rule refuses).
  Chapters on export — the last thing M2 owed — now land: `ExportWriter`
  (`app/Sources/ExporterWriter.swift`) REPLACED `AVAssetExportSession`
  outright, because two writing paths would make chapters, bitrate and output
  size depend on which one ran. Measured: `ffprobe -show_chapters` lists both
  markers of a two-chapter timeline, in mp4, mov and m4a alike, and rebases
  them onto an in/out range.
- **M3 — Polish: part done.** In: actions (evaluated in `actions.rs`) plus
  corner radius, colour controls and chroma key, all rendering through
  `Compositor.metal`. **Shadow now renders** — `MetalRenderer.encodeShadow`
  runs spec §7.5's three steps (the layer redrawn into a canvas-sized mask
  with `LayerUniforms.shadowMask = 1`, `MPSImageGaussianBlur`, then a tinted
  full-canvas quad) before each shadowed layer's own pass. `blur` and
  `distance` are SOURCE pixels scaled by the layer scale; `angle` is degrees
  from the right, counter-clockwise (`model.rs`), which the y-down canvas
  turns into a down-and-right default. Chroma key has its inspector group and
  a canvas eyedropper (`VideoPane.chromaSection`,
  `EditorViewController+Eyedropper.swift`, `CanvasEyedropperSession`).
  **GIF and APNG export are in** — `gif` and `apng` are presets like any
  other, resolving to `avf_preset: null`, which routes
  `Exporter.pipeline(...)` to `ExporterImageSequence.swift`'s
  `CGImageDestination` writer instead of `ExportWriter`; both refuse past
  600 frames rather than truncate. The export sheet's Quality row and the
  `export` tool's `video_bitrate` / `audio_bitrate` write the core's two
  override keys in bits per second.
  **The schema is version 2** (`RC_FORMAT_VERSION` in `core/src/format.rs`
  and the header): filters, reflection, spotlight, `Source::Media.reversed`,
  audio pan / compressor / noise reduction, and `Project.nests` all persist,
  and a version-1 file still opens — including the one shape serde cannot
  absorb with a default, a v1 nest clip whose `project` was a path string,
  which `migrate_1_to_2` rewrites into a named empty `Nest`.
  **Filters, reflection and spotlight render**, through three new passes in
  `Compositor.metal` (blur/sharpen/pixelate fold into the sample, the four
  point filters run in slot order after) with their inspector sections in
  `VideoPane.swift`; measured, all seven filters change the frame and
  clearing the stack returns it byte-identical.
  **SRT captions import** (`CaptionImporter.swift`, File ▸ Import Captions…
  and `import_captions`), **Consolidate Media works**
  (`MediaConsolidator.swift`; the package survives being moved), and
  **ffmpeg-assisted import is in** (`FFmpegRewrap.swift`, opt-in through
  `-RCFFmpegImport always`, binary overridable with `-RCFFmpegPath`;
  conversions live in `~/Library/Application Support/Reelcut/Rewrapped/`,
  never in the package — spec §11 says why). With neither ffmpeg nor a
  cached conversion an MKV fails exactly as it always did.
  **Nests render.** `core/src/nest.rs` flattens a nest clip into one
  `Instance` per drawing clip inside it, and `recipe.rs`, `audio.rs` and
  `transition.rs` all consume instances, so the plan, the envelopes and an
  overlap INSIDE a group work on the same terms as at the top level. The
  outer transform folds into each inner layer (`CONTRACT §4`), the layers are
  clipped to the nest's frozen canvas through the recipe's `clip_rect`, and
  the nest clip's own volume/mute multiplies what is under it. Measured
  against the built app: nesting a timeline renders a byte-identical frame,
  and `nest` → `unnest` returns the clip content unchanged (fresh ids, like
  split/join). ⌘G / ⇧⌘G are `EditorViewController+Nest.swift`. **You cannot
  edit inside a nest**, and the block is in the core, not the view: every
  `clip` argument in the op table resolves through `Project::clip`, which
  searches `self.clips` only, so no op can name a nested clip. The round trip
  (⇧⌘G, edit, ⌘G) is the way in until an op can name one — that file's module
  doc argues it at length, and spec §4.4 records it.
  **Reverse is in** (`ReverseRenderer.swift`): `Source::Media.reversed` is
  resolved to `cache/reversed/<media id>-<digest>.mov` inside the package,
  rendered on demand behind a progress sheet, substituted per CLIP by
  `CompositionBuilder` (a boomerang is one media, two clips), slated while
  pending. The three audio DSP fields **have both halves** now — the Audio
  pane writes them and `AudioTap.swift`/`AudioDSP.swift` run them through an
  `MTAudioProcessingTap` on the mix, which playback and export share. Pan is
  a constant-power law normalised to unity at centre (so 0 is an exact
  bypass), and noise reduction delays its track by 512 samples.
  Not started: **filters as animatable action targets** beyond what
  `clamp_video` already bounds. `AudioProps.mono` is still unimplemented —
  the tap could fold it, but turning it on would change how existing
  projects sound.
  Two measured things worth knowing before you chase them: **audio export is
  not bit-deterministic near a duck ramp edge** (three exports of one
  unchanged project gave two distinct results differing by 38 samples of one
  16-bit LSB, −90 dBFS, in an 8 ms window at the release edge — AVFoundation's
  mix, no nest involved), and **`add_clip` onto an overlap gives the new clip
  the default `cross_dissolve`**, so a "no transition" baseline has to be
  built by moving clips apart, not by clearing the kind — an overlap with no
  kind still dissolves (`transition.rs`: `unwrap_or_default()`).

Keep this file current as code lands.
