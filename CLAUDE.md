# CLAUDE.md

Reelcut — a screencast-style video editor for macOS: a Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`.

**It builds and runs.** M1 (Cut) is done and verified against spec §10; most
of M2 landed with it.

Four things in `designs/`, and you want all of them:

- `designs/reelcut-design.md` — the normative spec. The schemas (§5), the op
  table (§6) and the architecture (§7) govern any change to either side; §11
  holds decisions already made, which are not to be re-litigated.
- `designs/reelcut-roadmap.md` — the record of M1–M3: what proved each
  piece, what still needs a person at the machine, and the known limits.
- **`designs/reelcut-roadmap-2.md` — what to build next, in ten phases**
  (cutting moves, clip identity, the screencast trio, captions and text
  animations, sound, looks, output, viewing, and entering a nest), each
  naming its ops, schema bump, files, MCP mirrors and the proof that closes
  it. **Start here if you are picking up new work**, and update its status
  table as phases land.
- `designs/design_handoff_reelcut/` — the chrome cleanup and the identity,
  now SHIPPED. Its `README.md` is the normative source for the redesign's
  metrics (spec §3–§4.4 summarises them); the two `.dc.html` files are
  browser prototypes, not code to port, and `logo/` is the identity master.

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release  (358 black-box tests)
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
  src/                 model(+_query/_props/_regions) time edit(+_clip/_edge/
                       _insert/_props/_track/_time/_paste/_nest/_action/_zoom)
                       props_check actions transition evaluate recipe nest
                       audio snap format export(+_size) agent ffi*
  tests/               black-box, through the FFI (core/CLAUDE.md)
app/
  Sources/             AppKit app, programmatic UI (app/CLAUDE.md has the map)
  Resources/Shaders/   Compositor.metal — the per-layer compositing pass
  Bridging/            the bridging header importing core/include/reelcut_core.h
designs/             reelcut-design.md — normative spec;
                     design_handoff_reelcut/ — the shipped chrome + identity
tools/proof/         the MCP client, the per-phase proof scripts, and harness/ —
                     the offscreen chrome renderer ("Seeing the chrome" below)
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
`http://127.0.0.1:<port>/mcp` — 70 tools: one per §6 op (53) plus the
seventeen app-state tools: `open_project`, `new_project`, `save_project`,
`get_project`, `import_media`, `import_captions`, `export_captions`,
`transcribe`, `consolidate_media`, `detect_silence`, `set_playhead`,
`set_range`, `set_selection`, `undo`, `redo`, `render_frame` and
`export`.
`render_frame` writes a PNG and returns its path, so a script can diff it
against `ffmpeg`-extracted source frames; `export` waits for the file.

**`tools/proof/` holds the scripts that do this** — an MCP script per
road-map-2 phase over a dependency-free client (`mcp.py`), and from phase 2
an offscreen-chrome script beside it (`phase2_chrome.py`, over `harness/`,
which needs no port). Its README says how to make the test media and run
one; every claim in them is a placement read back through `get_project`, a
BYTE comparison of two PNGs (`render_frame`'s, or the harness's, where the
claim is also WHERE the changed pixels landed), or a sample-for-sample
comparison of two exports decoded to PCM (which needs `ffmpeg` at proof
time). Before trusting any MCP proof, `grep "Reelcut: " /tmp/reelcut-<port>.log`
must print nothing — that prefix is the startup parity check complaining.
Add the next phase's proof there rather than writing a throwaway.

Spec §10's per-step verifications are the acceptance tests. Steps 3, 4, 5, 7,
9, 10, 11 and 12 have been run against a built app and passed; 1 and 2 are
what `make app` and `make test` check every time. **Steps 6 (timeline view)
and 8 (canvas overlay) have now been LOOKED AT** — see "Seeing the chrome"
below. Still unchecked by a human: step 4's "the clip plays with audio" and
step 5's 60 fps, neither of which a still frame can answer.

## Seeing the chrome

`screencapture` needs a Screen Recording grant the agent's terminal does not
have, and it silently writes a black PNG rather than failing. The way to LOOK
at the chrome is therefore to render it offscreen, and the program that does
it is in the tree: **`tools/proof/harness/`** compiles every file in
`app/Sources` except `main.swift` with a `main.swift` of its own, links
`core/target/release/libreelcut_core.a`, opens a `.reelcut` package through
`ProjectDocument.read(from:ofType:)`, puts an `EditorViewController` in an
`NSWindow`, and `cacheDisplay(in:to:)`s the
content view into a PNG — the same paint path the window uses, no TCC grant,
either appearance on demand, and how the redesign was checked.

It captures on SETTLE, not after a fixed number of runloop turns: capture,
spin, capture again, and write only when two consecutive captures are
byte-identical (40 turns, then a warning and the last capture). A spin count
is a guess about how long the last relayout takes, and asking the layout is
better than guessing whatever else is true.

**That is not what makes a render reproducible, and the distinction cost
phase 4 a gate.** The settle was landed as the cure for a bistable
inspector — the Actions pane sometimes at its intrinsic height and sometimes
stretched, a render deterministic within a process and different across
processes — and it cured nothing, because a settle can only wait out a
layout that is still MOVING and both of those had already stopped. The
cause was an ambiguous constraint (`InspectorPane.swift`: a bottom pin at
`.defaultLow` tying with a section's own default hugging of 250, so the
solver could stretch a section or move the pane's bottom for the same
price), and it is fixed there, at 249. **Identical, stable, DIFFERENT
output across processes is an ambiguity to find, not a race to out-wait** —
reach for Auto Layout priorities, not for more turns.

```sh
tools/proof/harness/build.sh     # ~30 s into tools/proof/work/harness/, skipped when fresh
                                 # (--force rebuilds); needs the staticlib from make test
tools/proof/work/harness/harness <project.reelcut|welcome> <out.png> <light|dark> \
    [w] [h] [selectIndex] [playheadSec] [sizeIndex 0-2] [clip|media|document] \
    [candidateSpans] [expandSections]
tools/proof/work/harness/harness cues <words.json> <out.json>
```

The PNG is at the main display's backing scale (2880×1724 for the default
1440×862 window on a Retina Mac). The preview well comes out black — a Metal
layer has no drawable offscreen — which does not matter, because the chrome
is the point. Selection, the playhead, the S/M/L size, Remove Silences'
candidate spans (`"1-2,6-7"`, seconds) and the inspector sections to open
(`"video.obscure"`) are VIEW state and not in the package, so the arguments
set them — the last two exist because a sheet cannot be put up offscreen and
a `defaultExpanded: false` section would otherwise show only its header.
Both default to `-`, so a nine-argument call renders the bytes it always
did. The harness also pins every
`UserDefaults` key the chrome reads (the persisted pane sizes, collapsed
state, track height, snapping, guides and the Document tab's checkbox) plus
`AppleShowScrollBars = Always` in the argument domain, so two renders of one
package are byte-identical on one machine, mouse or no mouse.
`tools/proof/phase2_chrome.py`, `phase3_chrome.py` and `phase4_chrome.py`
are the proofs built on it: a pixel diff of two renders, measured against
rectangles from the layout constants. `expandSections` is what lets one
photograph a section built `defaultExpanded: false` — phase 4's Animation
section is the second to need it — and the fact that it was already there
is worth saying, because a proof that quietly grows its own instrument is
not a proof.

**The second form photographs nothing**, and it is here for the reason to
remember when the next piece of app arithmetic has no caller a script can
reach. `CaptionCues` — the four rules that turn recognised words into cues
(phase 4a) — is Swift, and in the app nothing reaches it until a recogniser
has produced words, which needs a grant. The harness is the ONE binary in
the tree that links `app/Sources` from outside the app, so it grew a mode
that runs the builder over a word list from a file and writes the cues as
JSON, and `phase4_chrome.py`'s section 8 asserts the four rules over its
answer at their boundaries. The mode was ADDED beside the render arguments
rather than folded into them, so every earlier chrome script's argument
positions still hold.

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
  **The schema is version 5** (`RC_FORMAT_VERSION` in `core/src/format.rs`
  and the header). Version 2 was M3's: filters, reflection, spotlight,
  `Source::Media.reversed`, audio pan / compressor / noise reduction, and
  `Project.nests` all persist, and a version-1 file still opens — including
  the one shape serde cannot absorb with a default, a v1 nest clip whose
  `project` was a path string, which `migrate_1_to_2` rewrites into a named
  empty `Nest`. Version 3 is road map 2's phase 2 — a clip's `name` and
  `label`, a track's `solo` — and has no migrate step, since all three
  default (`format.rs` says why it bumps anyway); version 4 is phase 3's
  `video.obscure` and version 5 phase 4's `text.animation`, both on the
  same terms.
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

- **The chrome cleanup and the new identity: done**
  (`designs/design_handoff_reelcut/`). The three things the user named — a
  grab-bag toolbar, an out-of-place Export button, and clips you could not
  tell apart — plus the identity around them.
  **Identity**: `AppIcon.appiconset` is the two-clips-and-a-playhead mark, and
  `BrandMark.swift` draws the same geometry for the welcome lockup and the
  About panel. No blend mode anywhere in it (the motif it replaced was the
  app's only `.multiply`), and it holds at 16 px.
  **Toolbar** (`EditorViewController+Toolbar.swift`): transport · timecode —
  view · Export, and nothing else. The three clip actions went down to the
  timeline bar, the document meta went up to the title bar's subtitle, and
  Export is an `AccentButton` — flat, 4 pt radius, `DS.accent` — not the
  system pill. `StickerButton` survives for the sheets and the welcome screen.
  **Timeline bar** (`TimelineBar.swift`): a fixed selection block at the left
  edge, the eight clip actions, snap, the zoom cluster, S/M/L — and S/M/L now
  drives REAL heights, per track KIND (`DS.trackHeights`, text/video/audio),
  which is why `TimelineLayout.rowTop` is a prefix sum and not a multiply.
  **Clips are objects** (`TimelineClipDrawing.swift`): a 3 pt-inset body with
  a hairline border, a 16 pt name strip carrying the kind symbol, a filmstrip
  under a 54 % tint wash, trim grips on the selected clip only, and a
  transition zone hatched at the design's 3 pt on 7 pt PERPENDICULAR period
  (`TimelineDraw.hatch` steps along X on a 45° line, so the call site scales
  the spacing by √2).
  **Inspector**: six tabs became three (`ClipPane.swift`), with a selection
  header, per-section summaries, and sections chosen by the selection's kind.
  Two things worth knowing before you touch it: an `InspectorPaneView` is
  `isFlipped` so its scroll view starts at the TOP, and the section
  collapsed-state key records COLLAPSED, so the default applies only when
  nothing is stored.
  Fixed along the way, both app-wide and neither strictly the redesign's:
  **an audio-only file used to read as video everywhere** (the tint asked
  `enabled.video`, the Detach switch, instead of whether the file has
  pictures — `ClipKindStyle` now takes the snapshot), and **every custom
  control's tooltip was dead**, because `trackingAreas.forEach(removeTrackingArea)`
  takes `NSToolTipManager`'s area with it and nothing puts it back.
  Two deviations from the handoff, both deliberate: the Clip tab keeps the
  panes' existing sections rather than merging them into the five the mock
  sketches (merging would delete every per-section Reset), and the transport
  buttons are 34 pt rather than 30, because SF Symbols' `backward` measures
  exactly 30 pt at the 19 pt the same document asks for.

- **Road map 2, phase 0 — Groundwork: done.** `core/src/model_query.rs` took
  the lookups, `Project::new`, `validate` and the source-window arithmetic
  (`content_length`, `source_head`, `source_length` — the three measurements
  every placement op clamps against) out of `model.rs`, which is now the
  schema and its serde defaults and nothing else. The README's stale counts
  went with it, spec §9 grew a "proposed, not yet bound" table so a phase
  that binds a key checks for a conflict first, and spec §11 records the
  decision that speech recognition does NOT earn a second `async` exception.
- **Road map 2, phase 1 — Cutting moves: done.** Six ops, two gestures,
  three keys, no schema change.
  `core/src/edit_edge.rs` holds **`slip`** (the source slides under a fixed
  clip; a `still` moves the frame it holds; any other source is an `Err`
  under the non-media rule, which the module doc of `edit.rs` now states in
  four names rather than three) and **`roll`** (the hard cut moves and
  nothing else does; the predecessor is whatever ends EXACTLY at the clip's
  start, so a gap or an overlap refuses). `core/src/edit_insert.rs` holds
  **`insert_clip`** and **`overwrite_clip`**, both compositions of
  `split_clips` + `insert_time` + `add_clip` made one op so a drop is one
  undo step — and because the composition carries a rule neither half states:
  an insert cuts only the DESTINATION track and then shifts every unlocked
  one. `edit_time.rs` gained **`lift_range`** (the range cut with the hole
  left open) and **`close_gap`**, which refuses rather than closing part of
  the way; its `ripple_delete_range` was refactored onto the same
  `ordered_range` + `clear_range` pair, so a lift and a ripple cut
  identically and differ only in the shift.
  UI: ⌥⇧-drag a body slips and ⌥⇧-drag an edge rolls (`SlipSession` /
  `RollSession` in `TimelineSessions.swift`, begun from
  `EditorViewController+Edge.swift` because `TimelineView.swift` is frozen —
  `dragSnapper` and `makeSnapper` became internal for it, and both cases
  short-circuit BEFORE `selectClip`, which would read the ⇧ as "toggle
  membership" and drop the clip out of the selection on its way into its own
  slip). `,` / `.` nudge by a frame, ⇧ by ten (both `,` and `<` are matched,
  since `charactersIgnoringModifiers` keeps Shift applied). ⌫ with a range
  and nothing selected LIFTS — the Delete menu item's validation had to move
  out of its group for it, because a modifier-less key equivalent is
  resolved ahead of the first responder. Double-clicking an empty lane span
  closes that gap; Clip ▸ Close Gap does the playhead's.
  Insert / overwrite are reachable four ways: Edit ▸ Insert at Playhead and
  Overwrite at Playhead, the Media row's context menu, and an ⌥ / ⇧⌥ drop
  (`MediaDropMode`, read from `NSEvent.modifierFlags` at the drop, since
  `NSDraggingInfo` carries none). The Edit-menu pair needed a media
  SELECTION, which the app did not have: `ProjectDocument.selectedMedia` is
  the fourth piece of view state, clamped like the other three, drawn by
  `MediaRowView` and stored on the document because `MediaPane` is rebuilt
  whole whenever the media list changes.
  Measured: `core/tests/edge.rs` (16) and `core/tests/insert.rs` (10) plus
  three in `edit_tests.rs`; slip-and-back and roll-and-back compare whole
  documents byte for byte, and the insert/overwrite tests assert on what did
  NOT move as much as on what did.
- **Road map 2, phase 2 — Clip identity: done.** Three fields, two ops,
  one argument, schema version 3.
  `Clip.name`, `Clip.label` and `Track.solo` are the LAST keys of their
  structs (`core/src/model.rs`) and all three default, so
  `RC_FORMAT_VERSION` went to 3 with no migrate step — `format.rs` says why
  the bump still matters — and `core/tests/schema_v3.rs` opens version-1
  and version-2 fixtures and reads the new keys' order off the written
  text, since a parsed `Value` sorts them. `model.rs` was over the cap, so
  the §5.2 property types went out FIRST, into `core/src/model_props.rs`
  (the schema's vocabulary, where `model.rs` is its shape; re-exported
  whole, so every `crate::model::X` path held; 939 → 462), and
  `edit_props.rs`'s range checks followed into `props_check.rs` when
  `set_clip` took that file over the line.
  **`set_clip` is the fifth patch op** — `{clips, patch: {name?, label?}}`
  in `edit_props.rs`, NOT the road map's two top-level arguments, and that
  is the phase's one deviation from its plan: the op envelope reads an
  absent optional and an explicit `null` as the same thing and the crate
  has no tri-state argument idiom, while a patch already has the one
  wanted (absent keeps, `null` clears) and the Swift side already had
  `T??` patches and `patchArg`. Inside it an empty string clears too, after
  the trim a name gets, because an unnamed clip is `None`; an unknown key
  is an `Err`, checked before the ids. A split, duplicate, detach or paste
  carries name and label along (they clone the clip); `paste_attributes`
  never does. `set_track` gained `solo`.
  **`paste_attributes`** (`edit_paste.rs`, beside the payload it reads)
  copies the Copy payload's EARLIEST clip's property groups (at one start
  the front-most, then the lower id — never the array's first, which is
  creation order) onto each target,
  REPLACED whole, never merged — video and audio whole, transform included
  (`audio.muted` and `keep_pitch` travel; they are properties like
  opacity); text but `content`; shape but `kind`, `width`, `height`,
  `from`, `to`. `groups` absent means every group BOTH sides have,
  silently skipping the rest; a named group either side lacks is an `Err`,
  all-or-nothing; each copied group passes the range checks a patch does
  (`Project::check_group`). Speed, enabled, actions, the transition, the
  source and identity stay.
  **Solo** is a zero envelope like mute, decided in `audio.rs::Voice::of`
  against the stage's container track set — `silenced`: `muted ||
  (any_solo && !solo)`, so mute wins, a soloed track with nothing audible
  still silences the rest, a nest's tracks are judged among themselves
  and a timeline solo reaches a whole nest through its enclosing stage.
  `plays_audio`, `assign` and the plan's segments are untouched, so a solo
  toggle changes ramps only, and `plan_text()` of "solo A" is
  byte-identical to "mute every track but A". `nest` copies `solo` into
  the nest's own track as it copies `muted`.
  UI: rename by double-clicking a clip (`TimelineView+Rename.swift`, over
  the one editor the view keeps for tracks and markers; the frozen file
  holds the `clicks == 2` hook — before `selectClip`, like the ⌥⇧ slip
  branch — and a `relocateRename()` at the end of `rebuildLayout`, which
  moves the open field to the new layout's rect, or ends it with its
  commit DROPPED when its clip is gone), in the
  Clip tab's header field (`ClipSelectionHeaderView`, `ClipPane.swift`)
  and Clip ▸ Rename… ⇧⌘R (`EditorViewController+Identity.swift`). A label
  is a 6 pt dot at the right end of the name strip and beside the header's
  name, and Clip ▸ Label ▸ is a tagged submenu over `ClipLabel.allCases` —
  `ClipLabel.swift` is the ONE home of the marker-colour vocabulary, and
  the ruler's marker flags read it now too; the tint stays the kind's.
  Solo is the fourth header toggle (`headphones`, index 3; its text
  fallback is S, as H/M/L are the other three's — the glyph is what draws) and
  Track ▸ Solo; ⌥⌘V is Edit ▸ Paste Attributes over the existing
  pasteboard type, sent with no `groups` (the default rule). The mirror is
  `set_clip`, `paste_attributes` and `set_track`'s `solo`, and `set_clip`'s
  handler adds a per-key TYPE check, because `patchArg` cannot refuse a
  number for a `String??` — it decodes as a clear.
  Worth knowing: the shared rename editor DROPS an unchanged commit (an
  accidental double-click would otherwise pin a clip's fallback as its own
  name) and an empty one (right for a track or a marker, whose names cannot
  be cleared), so the strip cannot
  clear a name — the Clip tab's header field is where an emptied name goes
  back to the fallback. A solo belongs to its TRACK, so nesting a clip off
  a soloed track onto an unsoloed one (the nest clip lands on the
  selection's front-most track, and the solo stays behind on the emptied
  one) silences it, exactly as moving it there would — a documented limit,
  not a bug. And a rename committed inside another gesture (type, then
  click a header toggle without Enter) merges into that gesture's undo
  step, and Escape does not cancel the field — both pre-existing for track
  and marker renames.
  Measured (`tools/proof/phase2_proof.py` over MCP against `make app`'s
  binary; `tools/proof/phase2_chrome.py` offscreen): soloing the back track
  of a two-tone project exports audio sample-for-sample identical to muting
  the front track (0 of 477,056 samples differ) and to a project holding
  only that tone; a track both soloed and muted exports digital silence,
  equal to muting both; the frame over a picture track is byte-identical
  before and after a solo. `set_clip`'s `null`, `""` and a blank string all
  clear, a padded name is trimmed, identity and a wrong-typed key are
  refused by name, and a split carries name and label to both halves.
  `paste_attributes` leaves both targets' video and audio equal to the
  source's, the text's `content` and all eleven keys outside the groups
  byte-identical, and undoes in one step with the frame restored
  byte-identically. Offscreen, a rename changes exactly three pixel
  clusters — selection block, Clip header, name strip — and nothing else;
  a label changes only the strip's and the header's right ends, red and
  blue differ only there and read as their inks, and the body's tint pixel
  is unchanged; a solo lights the headphones box and nothing else. Worth
  knowing beside the M3 note on audio export: two exports of an unchanged,
  duck-free, fade-free two-track project decode byte-identical, so the
  wobble is confined to duck edges and a solo/mute proof needs no tolerance.
- **Road map 2, phase 3 — The screencast trio: done.** One schema key at
  version 4, two ops, one app-state tool, three features that make a
  screen recording cut fast.
  **`video.obscure`** (`core/src/model_regions.rs`) is a list of at most
  four regions that HIDE what is under them — `{shape, x, y, width,
  height, feather, kind, amount}`, defaulting to a rect 480×270 at the
  centre, feather 20, **`pixelate` at amount 1**. That default is the
  opposite of a filter's half-strength blur for the opposite reason: a
  filter has to be visible without destroying the frame, while a region
  that only half hides has failed at its one job, and a blur at the
  shader's maximum radius is soft enough to read a large password field
  through. `shape` REUSES the spotlight's `SpotShape`; `kind` is a closed
  `ObscureKind`, not a narrowed `FilterKind`, so a hand-written `"sepia"`
  is refused on the way in rather than clamped later. Every field defaults,
  so `RC_FORMAT_VERSION` went to 4 with no migrate step — `format.rs` says
  why the bump still matters — and it is written through `set_video` like
  any other video property, with no op of its own. The types went into a
  new `model_regions.rs` (218) as `model_props.rs` crossed the cap at 633
  and came back to 498: the boxes drawn ON the picture are one concern,
  sharing one coordinate frame and one shape enum.
  **`ripple_delete_ranges`** (`edit_time.rs`) is the silence cut: the pairs
  are ordered, MERGED — touching as well as overlapping — and then cut and
  closed right to left, with `set_gained_transitions` once at the end. It
  is defined as merge-then-cut and NOT as N singular ops, because a cut at
  a boundary that no longer exists mints a fragment and burns an id; and
  `ripple_delete_range` is now `self.ripple_delete_ranges(&[[from, to]])`,
  one implementation per algorithm, proved by `edit_tests.rs` gaining 220
  lines and losing zero.
  **`add_zoom_action`** (`core/src/edit_zoom.rs`, 390) turns a rectangle
  into an action: its module doc IS the placement equation, between the
  region frame (spec §5.3) and canvas pixels. `fit`/`fill` are measured
  THROUGH the clip's rotation (a rectangle contains a rotated one exactly
  when it contains its four corners), rotation and crop are read from the
  clip evaluated at `at`, and the scale is clamped BEFORE the offsets are
  derived from it, so a region that wants more than ×10 still lands
  centred and only the magnification degrades. It composes `add_action` +
  `set_action` + `set_action_end` — one undo step, every refusal
  inherited — and calls `nest.rs`'s `rotate` (widened to `pub(crate)`)
  rather than writing a second rotation.
  **`detect_silence`** reads the PLAN, not the peaks alone: a bucket's
  loudness is `peak × envelope`, and since `audio.rs` expresses mute and
  solo as a ZERO envelope, both fall out for free with no second Swift
  copy of `silenced`. A tick covered by no scope segment is never a
  candidate — a hole in the timeline is not dead air — and the surviving
  runs lose their padding and snap INWARD, the conservative direction for
  a destructive edit. Two things are never IN a candidate, both settled by
  the review: a clip the mix has silenced, which is dropped from either
  scope rather than read as quiet (it covers its span while passing the
  quiet test at every tick, so a selected muted music bed proposed one cut
  across the whole song and the ripple took the voiceover under it); and a
  NEST, whose sound counts toward the test but which no candidate may
  intersect, because `Source::Nest` has no in point and splitting a nest
  clip strands its tail rather than trimming it.
  **The list-interpolation rule** is now the crate's, stated once in
  `actions.rs`: an end patch interpolates a list per index when the lengths
  match and each pair of entries agrees on its discrete fields, and
  switches at the end otherwise. `video.filters` and `video.obscure` are
  both governed by it and neither carries a line of its own code.
  UI: **Clip ▸ Remove Silences…** (`SilenceSheetController.swift`, its
  detector in `SilenceDetector.swift`) with the candidate spans shaded on
  the ruler and the lanes (`DS.timelineCandidateShade`,
  `TimelineView+Candidates.swift`); **bare Z** arms and disarms a canvas
  region mode (`EditorViewController+ZoomRegion.swift`, `CanvasSessions`'
  `ZoomRegionSession`) whose band drags free with the rectangle it will
  actually resolve to ghosted dashed beside it; and the Video sections
  gained **Obscure** (`VideoPane.obscureSection`) plus Zoom to Region… /
  Zoom Back buttons.
  Six deviations worth knowing, all argued where they live: **`curve` is a
  sixth argument** on `add_zoom_action` (defaulting to the eased-both-ends
  form, not `Curve::default()`'s linear), because a screencast zoom that
  starts and stops abruptly is the thing the feature exists to avoid and
  adding it later would mean a second op in one gesture; **the obscure
  shader stage runs at 4b**, between the sharpen and the point filters, not
  after them — it must follow the sharpen, whose detail term is built from
  the RAW texture and would put the hidden detail straight back, and
  precede the point filters, or a region on a sepia layer would show as an
  ungraded hole (`Compositor.metal`'s order-of-operations comment argues
  it); **the widened discriminant set `{kind, shape}` applies to LIST
  ENTRIES only**, so `video.spotlight`'s shipped animation is byte for byte
  what it was, and a regression test pins it; **⇧ chooses fill** during the
  canvas drag, which is the only way `fill` is reachable from the canvas at
  all; **the sheet spells the removed total as a timecode** ("23 cuts ·
  removes 00:00:04:12") through `ReelTime.format`, because inventing a
  second spelling of a time is what that formatter exists to prevent; and
  the region default kind is **pixelate**, not the blur a reader coming
  from `Filter` would expect.
  Measured: `make test` 338 (284 before — `schema_v4.rs` 12, `zoom.rs` 32,
  `edit_tests.rs` +5 and `schema_v2.rs` +5, plus `model_tests.rs`'s fixture,
  which grew two regions and no test),
  `make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors and
  the same 4 AVFoundation warnings, `make app` building, the catalog at 68
  tools and the startup parity log EMPTY. Against that binary over MCP: a
  320×180 region on a 640×360 clip under `fit` wrote `{scale: 2, x: 0,
  y: 0}` and a null region wrote the base transform back under the undo
  name "Zoom Back"; `detect_silence` answered with −40 dBFS, 0.5 s, 0.1 s
  and the scope it used; `[[1 s, 2 s], [3 s, 4 s]]` in one
  `ripple_delete_ranges` turned one 5 s clip into three 1 s clips; and a
  wrong-typed tick came back as `ranges[0][1] must be a time in ticks`,
  an absent `region` by name. The phase's own scripts are
  `tools/proof/phase3_proof.py` (**121/121** over MCP — 91 at the landing,
  plus the thirty the review's fixes brought),
  `phase3_silence_scope.py` (**8/8**, the review's own: what the detector
  must NOT find when something is muted) and
  `phase3_chrome.py` (**33/33** offscreen — the candidate wash and the
  Obscure section's rows; the preview well is black offscreen, so nothing
  about the PICTURE is claimed there), and phases 1 and 2 still prove at
  66/66, 85/85 and 26/26.
  **Reviewed by nine readers, six real defects fixed** — road map 2's
  phase-3 section lists them; the two with teeth were a blurred region
  ERASING a pixelated one it overlapped (both mixes sampled the raw
  texture, so the second won outright and the blur always ran second) and
  a silenced clip in the selected scope proposing to delete itself.
  Worth knowing before you chase them, none of them new defects: a PARTIAL
  entry in an action's end patch (`{"obscure": [{"amount": 1}]}`)
  interpolates smoothly and then takes `ObscureRegion::default()` for every
  key it omitted at the switch, because `merge` replaces a list rather than
  merging it — filters have had this since M3; a PIXELATED region takes one
  raw sample, so on a layer that also carries a global blur the blocks come
  out unblurred while the picture around them is blurred (the coarser of
  the two is what hides), while a blurred region combines in quadrature and
  is always at least as blurred as its surroundings; a region on a SLATED
  (missing-media) layer does nothing, the same posture the sharpen takes;
  the canvas band commits a RECT, so an ellipse is reached only through the
  section's Shape popup; stored regions are NOT drawn on the canvas outside
  the modal mode (drag handles for one are a hit-test family
  `PreviewCanvasView.swift` has no room for yet); where two regions cover
  one pixel the GREATER hiding wins and the other is not applied at all,
  so an overlap of a blur and a pixelate shows one of them and never a
  blend; adding or removing a region or a filter writes the BASE props even
  inside an action (a list of a different length cannot interpolate, so an
  end patch would swallow it); and a reversed clip
  INSIDE a nest is analysed unmirrored and cannot be named by the selection
  scope, because a nested clip has no id the snapshot can look up.
  Two limits older than the phase but reachable through it, both recorded
  and neither fixed: an instance DEADLOCKS somewhere past forty open
  documents, because nothing closes one (`tools/proof/README.md` measures
  it — relaunch between proof sessions rather than reading a hang as a
  failure); and on the MCP path a nested object inside a patch is decoded
  into a typed Swift struct and re-serialised, so a misspelt key inside one
  is DROPPED where the core would have named it and a known key the caller
  omitted is sent as its DEFAULT, which resets that field — `shadow` since
  M3, `obscure` now.
- **Road map 2, phase 4 — Words: done.** One schema key at version 5, NO
  new op, two tools (so the catalog is 70 and `OP_NAMES` is still 53), and
  captions in both directions.
  **`text.animation`** (`core/src/model_props.rs`) is `null` or
  `{kind, in, out}` — `typewriter`, `word_fade`, `line_rise` — as the LAST
  key of the text object, defaulting to `null` and, inside an animation
  that says nothing, to a one-second typewriter that does not un-reveal.
  `in` and `out` are DURATIONS from the clip's own first and last frame,
  not times. Every field defaults, so version 5 has no migrate step;
  `format.rs`'s paragraph restates the argument rather than pointing at
  version 4's, because a defaulted field is exactly the case where the bump
  looks like paperwork — unknown keys are ignored at every level by design,
  so without the gate a version-4 build would open the file, drop every
  animation on read and write the loss back on the next save with the text
  still on screen. `TextAnimationKind` is closed at three like
  `ObscureKind`, but its declaration ORDER is not load-bearing: the recipe
  carries the kind by NAME, where `ObscureKind`'s order is a shader
  discriminant.
  **The reveal is computed by the CORE** (`recipe.rs`, 567 — up from 331)
  and rides INSIDE a text layer's `source` object beside `hash` and `text`,
  as THREE keys emitted on every text layer whether it animates or not:
  `reveal` (0–1, 1.0 with no animation), `reveal_phase`
  (`"in"`/`"out"`/null — one number cannot say whether a typewriter is
  typing or un-typing, and a line rise falls rather than rises on the way
  out) and `reveal_kind` (the kind by name, or null). **`reveal_phase` is
  the ORDER the renderer draws in, not a label on the amount**, and the
  review is what settled that: `word_fade` and `line_rise` count their
  stagger from the other end while leaving, so the frame the phase turns on
  is a frame the picture mirrors on, and the one amount at which that is
  invisible is 1. An animation that fits its clip has a plateau to turn on
  (ties go to the arrival); a TENT — `in + out > duration`, which degrades
  rather than refusing — crosses BELOW 1 and used to flip there, so it now
  keeps the phase it began in for its whole life, the arrival's unless `in`
  is 0. The documented limit: a tent whose `in` is tiny but not zero reads
  `"in"` from its first frame to its last. The third key is a
  DEVIATION from the plan — road map 2's phase-4 section argues it — and it
  is forced by the decision beside it: the recipe STRIPS `animation` out of
  the text description it carries — so the computed reveal is the
  renderer's only account of it, and an unanimated clip's hash stays byte
  for byte what it was — which leaves nothing else to say which of three
  drawing routines to run. The hash COVERS all three, and that is what
  stops an animating layer being served a stale texture: Swift caches a
  paragraph under `"text:" + hash` and consults nothing else, so a reveal
  that changed the picture without changing the key would render correctly
  in a single `render_frame` and freeze during playback. Both halves
  measure against the CLIP's own duration, never the instance's visible
  end (`layer()`'s existing rule for clip time), so a nest clip's edge cuts
  a nested caption off mid-reveal rather than making it un-reveal early;
  and `in + out` longer than the clip DEGRADES to the smaller of the two
  ramps rather than refusing, because "too big for THIS clip" is a fact
  about a clip and not about the vocabulary, and a later trim would
  invalidate it anyway.
  **Swift draws it** in `LayerRenderers.renderText`: a grapheme-cluster
  prefix (typewriter), per-word alpha with a `wordOverlap` 0.5 stagger
  (word_fade), a per-line rise of `lineRiseFraction` 0.35 of the line's own
  height, masked by the box (line_rise), the backdrop at full opacity in
  every kind because it is the readability plate and not the words. The
  layout is ALWAYS the full text's, now built once into a `layoutCache`
  beside `sizeCache` and keyed without the reveal — `renderText` used to
  build a second framesetter over what `measure` had already framed — and
  `reveal = 1` takes the original single `CTFrameDraw` rather than the span
  machinery, which is what makes a full reveal byte-identical to no
  animation. The inspector's Animation section is `TextPane.swift`; it
  re-sends all three keys on every row, since a patch of a nested object is
  a REPLACEMENT.
  **Auto captions** are `Transcriber.swift` (File ▸ Generate Captions…,
  `TranscribeSheetController.swift`, and the off-main `transcribe` tool),
  and the plan's other deviation is that they transcribe EXTRACTED audio —
  each clip's own source window written to a temporary mono 16 kHz WAV,
  never the media file and never inside the package. Whether
  `SFSpeechURLRecognitionRequest` can read an arbitrary `.mov` is
  unanswerable here (the grant needs a frontmost app), and a design that
  works on the `say -o` fixtures and fails on every real clip is the worst
  failure shape available; it also bounds the work to what the timeline
  uses and leaves the time mapping with no `in` term at all. Three refusals
  are deliberate: the tool never calls `requestAuthorization` — the SHEET
  does, because a person opened it — and names the status instead; a
  reversed clip is refused with the non-media sources, because its words
  would come out backwards; and a transcript that would exceed `MAX_CLIPS`
  is refused in the LAYOUT, naming the cue count and the room left, where
  `check_caps` would have refused it with a message about clips. The
  framework's roughly one-minute ceiling per task is REPORTED, not chunked
  around: a run that stopped early answers `truncated` with the second it
  stopped at.
  **`CaptionLayout.swift`** is the placement both producers share, and it
  is placement ONLY. The road map says the four cue rules (≤ 2 lines, ≤ 42
  characters, ≤ 6 s, a frame between cues) are "factored out of
  `CaptionImporter.swift`"; NONE of them was ever in that file — an SRT
  brings its own line breaks — so they live in `CaptionCues` beside the
  layout, called only by the producer that has to invent line breaks.
  Moving them into the shared path would have silently re-wrapped every
  caption file that imports correctly today.
  **Caption export** is `CaptionExporter.swift` (File ▸ Export Captions…,
  `export_captions`): one track of text clips as `.srt` or `.vtt`, the
  track never guessed — a candidate is a track whose clips are ALL text,
  and none or several refuses and NAMES them. VTT escapes `&`, `<` and `>`
  and SubRip does not, so the two files are byte-siblings only for text
  holding none of the three; `srt` and `vtt` joined
  `AgentServer.replaceableExtensions`, or `{path: "talk.srt", format:
  "vtt"}` would have written `talk.srt.vtt`. A cue's TIMES survive the
  round trip at every ordinary rate: `format_timecode` rounds ticks to the
  nearest millisecond, 300 ticks at most, the importer turns a whole
  millisecond back into exactly 600 × ms ticks, and half a frame is 10,000
  ticks even at 30 fps, so the snap on the way back in can only find the
  frame the cue left. What a whole-millisecond frame buys is byte identity
  with the FILE — import snaps every cue to the grid, so a source written
  off it comes back written onto it — and the proof fixture is at 25 fps
  because 40 ms is a whole millisecond AND its times sit on that grid,
  which is what lets the claim be a byte comparison. The same fixture is
  imported at 30 fps as the other half of it, where the file must NOT come
  back and a second trip through the grid must move nothing: a tolerance
  instead of the pair would have passed against a build where the exporter
  did nothing.
  The three File-menu caption items sit together in the order a caption
  track comes into being and leaves again, and none takes a key
  equivalent.
  Measured: `make test` 358 (338 before — `schema_v5.rs` 11 and
  `evaluate_tests.rs` +9, plus `model_tests.rs`'s fixture, which grew the
  key and no test), `make lint` and `cargo fmt --check` clean,
  `make typecheck` 0 errors and the same 4 AVFoundation warnings,
  `make app` building, the catalog at 70 tools and the startup parity log
  EMPTY, and phases 1–3 still proving at 66/66, 85/85, 121/121, 8/8, 26/26
  and 33/33. The phase's own scripts are `tools/proof/phase4_proof.py`
  over MCP at **84/84** and `phase4_chrome.py` offscreen at **59/59** (the
  Animation section's rows — the preview well is black offscreen, so no
  reveal can be photographed); road map 2's phase-4 section carries what
  each one claims and the honest limit behind them. Transcription needs a
  TCC grant a headless run cannot obtain, so what the proof asserts about
  4a is that the grant-less refusals are exact — the caller's own mistakes
  answered above the grant, the grant's own sentence below them — and that
  a refused run places nothing. **The cue builder is proved in the
  HARNESS, not over MCP** — `CaptionCues` is Swift and nothing in a running
  app reaches it without a recogniser, so the harness grew a `cues` mode
  for it and `phase4_chrome.py`'s section 8 runs the four rules over word
  lists at their boundaries ("Seeing the chrome" says why that is the only
  binary that can). Until that landed the rules had no caller a script
  could reach, whatever these documents said.
  **Reviewed by eight readers, twelve findings fixed** — road map 2's
  phase-4 section lists the nine worth reading. The ones with teeth: a
  tent's `reveal_phase` flipped between two frames carrying the same
  reveal (the phase is the renderer's ORDER, not a label on the amount);
  an outlined glyph at a partial alpha composited its fill and its stroke
  SEPARATELY, so the outline sat at 0.75 while the word was at 0.5; one
  clip's failed audio extraction threw away a whole transcription and
  every earlier clip's cues with it; Generate Captions transcribed a clip
  whose audio is switched OFF, so Detach Audio doubled every caption; and
  `NSPopUpButton.addItem(withTitle:)` silently REMOVES a row with the same
  title, so the Export Captions panel could write a different track's
  captions and report success.
  Two things worth knowing before you touch the area, neither a defect of
  this phase: **`animation` is a nested object in a patch**, so it inherits
  the MCP decoder's replacement rule — a key left out of it comes back as
  the default 1 s typewriter, not as what the clip had — and **the
  offscreen harness was flaky, for a reason the phase guessed wrong**. It
  was blamed on linking `Speech.framework` and answered with a settle
  capture (see "Seeing the chrome"), which is worth keeping but fixed
  nothing: at the gate `phase3_chrome.py` still scored 29–33 out of 33 on
  identical input, because a settle waits out a layout that is still MOVING
  and this one had stopped — in two different places, once per process. The
  cause was an ambiguous constraint in `InspectorPane.swift`, where the
  pane's low-priority bottom pin at `.defaultLow` tied with an
  `InspectorSection`'s own default hugging of 250, so stretching a section
  and moving the pane's bottom cost the solver exactly the same. The pin is
  249 now; twelve harness renders of one package come back byte-identical
  and `phase3_chrome.py` is 33/33 run after run. **A proof that scores
  differently on identical input is an ambiguity to find, not a race to
  out-wait** — app/CLAUDE.md keeps that under `InspectorPane`'s pitfalls.

Keep this file current as code lands.
