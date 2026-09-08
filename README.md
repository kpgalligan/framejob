# Reelcut

A native macOS video editor in a screencast editor's shape: open a movie, arrange it on
layered tracks over a fixed canvas, trim, split, annotate, animate, export.
Swift/AppKit UI over a Rust core — the core decides, AVFoundation and Metal do.
Apple Silicon, macOS 15+.

The opening flow is the point. File ▸ Open on a `.mov` or `.mp4` (or a drop on
the Dock icon, or the welcome window's Open Video…) creates an *untitled*
project sized and rated to that file, with the file as the first clip on
Track 1, ready to cut. Save then writes a `.reelcut` package next to the
source.

The full design and implementation spec is `designs/reelcut-design.md`. It is
normative: §5.2 is the project schema, §6 the op table, §7 the architecture.

## What it does today

- **One kind of track.** Every track holds any clip — video, audio, image,
  text, shape. Tracks stack back to front; `tracks[0]` is the back.
- **Timeline** with a frame-accurate ruler, filmstrips and waveforms from a
  per-media cache, three row heights, magnify/⌥-wheel zoom about the cursor,
  and gesture sessions for drag, trim, rate-stretch (⌥ on the end edge),
  slip (⌥⇧ on a body), roll (⌥⇧ on an edge), marquee select, playhead scrub,
  marker drag, audio fade handles and track reorder — each one undo step,
  each snapping to clip edges, markers and the playhead (N toggles, ⌘
  suppresses). Double-clicking an empty span closes that gap; a media row
  dropped with ⌥ inserts and with ⇧⌥ overwrites. Double-clicking a clip
  renames it in place, a labelled clip wears a 6 pt dot in its label's
  colour on its name strip (the tint still says the kind), and a track
  header has eye, speaker, lock and headphones — solo.
- **Canvas** with an `AVPlayerLayer` under a transparent overlay: move, scale,
  rotate and crop handles, line/arrow endpoint handles, safe-area guides,
  snapping to the canvas centre and edges, inline text editing, a region
  band on Z for a zoom or an obscured area, and Fit / 50 % / 100 % / 200 %
  zoom stops.
- **Inspector** with three tabs — Clip, Media, Document. The Clip tab is a
  selection header — the clip's name, editable there for a single clip and
  the one place a name can be cleared back to what the clip shows, with its
  label dot — over the sections that selection's kind earns (transform,
  crop, filters, text, shape, audio, actions…), each collapsible. Every field
  reads the *evaluated* value at the playhead and writes to the clip's base
  props — or, when the playhead is inside an animation action, to that
  action's end state.
- **Editing**: move, nudge, trim, slip, roll, split, delete, lift, ripple
  delete (one range, or many at once), close gap, insert time, insert and
  overwrite, duplicate, speed, freeze frame, detach audio, transitions,
  actions, markers, tracks, canvas size and rate; a clip's own name and
  colour label (Clip ▸ Rename…, Clip ▸ Label ▸; a clip with no name of
  its own is called what it shows), solo (Track ▸ Solo — the other tracks
  in the same container go quiet, and mute still wins), and Paste
  Attributes (⌥⌘V: the copied clip's look onto the selection, each group
  replaced whole, a text clip keeping its words and a shape its kind and
  size). Every edit is a pure op in the Rust core returning a new
  immutable project handle, so undo is a stack of handles and a refused
  edit costs nothing.
- **The screencast trio.** **Remove Silences** (Clip ▸ Remove Silences…)
  finds the dead air — threshold, minimum length and padding, over the
  selected clips or everything audible — shades the candidate spans on the
  ruler and the lanes while you tune it, and takes them all out in one undo
  step, however many cuts that is. It measures what you HEAR, not what is
  in the file: the level it tests is the waveform peak times the mix
  envelope, so a muted or soloed-out clip is silent for free. **Zoom to
  Region** (Z, or the Actions section's button) is the screencast zoom:
  drag a rectangle over the selected clip and release, and the core solves
  for the scale and position that bring it to the canvas — through the
  clip's rotation and crop, eased at both ends, one action, one undo step;
  ⇧ fills the canvas instead of fitting, and Zoom Back animates to where
  the clip started. **Obscure** hides a face or a password field behind up
  to four blurred or pixelated regions per clip, each drawn on the canvas
  or typed into the inspector, each riding with its layer through every
  scale, move and rotation, and each animatable like any other property.
- **Words.** Captions go in and out: File ▸ Import Captions… reads a
  SubRip file, **Generate Captions…** writes one from the clip's own audio
  with on-device speech recognition (a language, a scope, a progress bar,
  and a grant macOS asks you for once), and **Export Captions…** writes a
  track back out as `.srt` or `.vtt`. A caption is an ordinary text clip
  either way, which is what makes burn-in on export free and lets you drag
  one to retime it. Text clips also arrive and leave under their own power:
  a **typewriter**, a **word fade** or a **line rise**, with separate in
  and out durations. The core computes how far along a reveal is, once per
  frame, so the preview, a rendered frame and an export cannot disagree
  about it.
- **Playback** over an `AVComposition` built from the core's composition plan,
  with a Metal compositor drawing every frame from the core's frame recipe.
  A property-only edit re-renders the paused frame without rebuilding the
  player (the plan JSON is compared as a string).
- **Export** through an `AVAssetWriter` over the same composition, the
  format (H.264, HEVC, ProRes 422, M4A, GIF, APNG) and the size chosen
  separately and both resolved by the core — the default size is the
  document's own, or for a GIF or APNG the format's cap fitted to it — plus
  an offline single-frame render used for verification.
- **MCP agent** (below): one tool per edit op, plus open/new/save/read,
  import, playhead, frame render and export.

Milestone status against spec §10: **M1 (Cut) is done** — every §10 check that
can be run offline was run against a built app, by driving it over MCP and
diffing `render_frame` and exported files against the sources. Most of M2
landed with it — text, shapes, transitions, audio
volume/fade/duck/detach, freeze frame, speed, the in/out range and the agent —
and **M2 and M3 are now done too**: chapters on export, nests, filters,
reflection, spotlight, reverse, the audio DSP, GIF/APNG export, SRT captions,
Consolidate Media and ffmpeg-assisted import. Beyond the spec,
`designs/reelcut-roadmap-2.md`'s phases 0 through 4 have landed — the
groundwork, the cutting moves, clip identity, the screencast trio, and now
captions in both directions with the built-in text animations.
`CLAUDE.md` carries the milestone record and `designs/reelcut-roadmap.md`
what still needs a person at the machine.

What has actually been checked, and what has not: the model, the ops, the
composition plan, the frame recipe, the compositor, save/open and export were
verified by driving the built app over MCP and comparing pixels and probed
files against the sources (spec §10 steps 3, 4, 5, 7, 9, 10, 11 and 12). The
parts only a person can reach — live playback and its 60 fps target (steps 4
and 5), the timeline view (step 6), the canvas overlay (step 8), the
inspector — are written and typecheck but have not been exercised by anyone.
Treat the gesture and playback bullets above as "implemented", not as
"observed working".

## Layout

```
core/                 Rust crate (staticlib) — the model, the ops, the plan,
  include/            the recipe, export settings and the MCP server
    reelcut_core.h    Hand-maintained C header: THE FFI contract
  src/                model.rs time.rs edit*.rs evaluate.rs agent.rs … (§7.10)
  tests/              black-box tests through the FFI
app/
  Sources/            Swift AppKit application (programmatic UI, no storyboards)
  Resources/Shaders/  Compositor.metal — the per-layer compositing pass
  Bridging/           Bridging header importing the Rust FFI header
designs/              reelcut-design.md — the accepted design and spec
project.yml           xcodegen definition — source of truth for the Xcode project
Makefile              Build orchestration
```

### `app/Sources` file map

| File(s) | Owns |
|---|---|
| `ReelCore.swift` | the **only** `rc_*` caller: `ReelProject` (handle + lazy snapshot), the typed `ReelOp` builders, `ReelTime`, `ReelSnap`, `ReelExport`, `RecipeSource` |
| `ProjectSnapshot.swift` | the `Codable` mirror of the §5.2 project JSON, the plan and the recipe, plus the §5.3 placement maths |
| `ProjectDocument.swift` | NSDocument, `.reelcut` package read/write, and the single mutation point (`applyEdit`, the live-edit trio, undo as a handle stack) |
| `MediaImporter.swift` | `AVURLAsset` probing (the one file allowed `async`/`await`), thumbnails, waveform peaks |
| `CompositionBuilder.swift` · `Compositor.swift` · `LayerRenderers.swift` · `Playback.swift` | plan → `AVComposition`; the `AVVideoCompositing` Metal pipeline; text/shape/image textures and the three text reveals the recipe asks for; the player and its rebuild-vs-refresh rule |
| `CaptionImporter.swift` · `CaptionLayout.swift` · `Transcriber.swift` · `CaptionExporter.swift` | captions in and out: the SubRip grammar, the placement every producer shares, on-device speech recognition and the cue builder over it, and the `.srt` / `.vtt` writer |
| `Exporter.swift` · `ExportSheetController.swift` | writing a file, and rendering one frame offline |
| `TimelineLayout.swift` · `TimelineSessions.swift` · `TimelineView.swift` | all tick↔point arithmetic; the gesture session structs; the timeline view |
| `CanvasSessions.swift` · `PreviewCanvasView.swift` | canvas geometry and gestures; the preview and its overlay |
| `InspectorPane.swift` · `InspectorViewController.swift` · `ClipPane` `MediaPane` `DocumentPane` (with `VideoPane` `AudioPane` `TextPane` `ShapePane` as section factories) | the binding that knows about actions, one file per tab, and the sections the Clip tab composes |
| `EditorViewController.swift` + `EditorViewController+{Timeline,Canvas,Inspector,Export}.swift` | wiring in the base file, features in extensions |
| `AgentServer.swift` + `AgentServer+{Arguments,Project,Clips,Tracks,Media,Render,History,Silence,Captions}.swift` · `AgentCatalog.swift` | the MCP endpoint, its handlers, and the tool catalog |
| `AppDelegate.swift` · `EditorWindowController.swift` · `WelcomeWindowController.swift` · `main.swift` | menus (nil-target selectors), window, welcome |
| `SpeedSheetController.swift` · `RelinkSheetController.swift` · `SilenceSheetController.swift` (with `SilenceDetector.swift` behind it) · `TranscribeSheetController.swift` | the remaining dialogs |
| `Theme.swift` · `Controls.swift` · `OptionControls.swift` · `Sheets.swift` · `EditorChrome.swift` · `FileDropView.swift` | shared chrome, copied from Rasterize |

## Building

Requires Xcode, Rust (cargo), and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make run        # build and launch
make test       # Rust core tests
make lint       # cargo clippy --all-targets -D warnings
make typecheck  # swiftc -typecheck of app/Sources — the ONLY authoritative Swift check
make project    # xcodegen generate
```

`Reelcut.xcodeproj` is generated — run `xcodegen generate` (or `make project`)
after editing `project.yml`, and don't commit the project file.

## AI agent access (MCP)

Tools ▸ Allow Agent Connections hosts an MCP server (streamable HTTP) inside
the app at `http://127.0.0.1:4817/mcp`. The menu item shows the live endpoint
while it runs and remembers the setting across launches.

To drive a build for verification, launch it with the agent already on — the
`-AgentServerEnabled YES` flag lands in NSUserDefaults' argument domain, which
is the same switch the menu flips, and `RC_AGENT_PORT` overrides the port (a
port already in use falls back to an ephemeral one, and the log line names
what it bound):

```sh
make app
RC_AGENT_PORT=4817 \
  build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
  -AgentServerEnabled YES
```

Then point any MCP client at the endpoint:

```sh
goose session --with-streamable-http-extension "http://127.0.0.1:4817/mcp"
```

The endpoint is **unauthenticated**: any local process may connect while it
runs. It is off by default.

### The tools

**One tool per row of the op table** in spec §6 and the module doc of
`core/src/edit.rs`, with the same name and the same argument names —
`add_clip`, `add_text_clip`, `add_shape_clip`, `insert_clip`,
`overwrite_clip`, `move_clip`, `trim_start`, `trim_end`, `rate_stretch`,
`slip`, `roll`, `split`, `delete`, `ripple_delete`, `ripple_delete_range`,
`ripple_delete_ranges`, `lift_range`, `insert_time`, `close_gap`,
`set_speed`, `set_reversed`,
`freeze_frame`, `detach_audio`, `duplicate`, `paste`, `paste_attributes`,
`nest`, `unnest`, `set_video`, `set_audio`, `set_text`, `set_shape`,
`set_clip`, `set_enabled`,
`set_transition`, `set_transition_duration`, the four action ops and
`add_zoom_action` beside them, and the
track, marker, canvas and media ops — plus the app-state tools below. The
count of each is `rc_op_names`' length and the catalog's, and the startup
parity check compares them, so it is one number in the code and not one
here.

| Tool | |
|---|---|
| `open_project {path}` | a `.reelcut` package, or any movie/sound/picture, which opens as a new untitled project around it |
| `new_project {path?}` | a blank 1920×1080 / 30 fps project, saved straight away when given a path |
| `save_project {path?}` | returns once the package is really on disk |
| `get_project` | the whole §5.2 JSON, plus the playhead, selection and in/out range that live only in the app |
| `import_media {path}` | probes a file and returns the **new media id**; `add_clip` then places it |
| `import_captions {path, track?}` | an SRT file as text clips (File ▸ Import Captions…) |
| `consolidate_media {}` | copies every referenced file into the package (File ▸ Consolidate Media…) |
| `transcribe {clips?, language?, place?}` | on-device speech recognition into caption clips (File ▸ Generate Captions…). Returns the cues in ticks whether or not it places them, and `place: false` changes nothing at all. macOS gates speech recognition and this tool never asks: without the grant it refuses with the status named, since the system prompt needs a frontmost app and an agent-driven one never is |
| `export_captions {track?, path, format?}` | one text track out as `.srt` or `.vtt` (File ▸ Export Captions…). The track is never guessed — with no all-text track, or more than one, it refuses and lists the candidates |
| `detect_silence {clips?, threshold_db?, min_length?, padding?}` | the quiet spans of the timeline, which `ripple_delete_ranges` then cuts — the same detector Clip ▸ Remove Silences… uses, so an agent and the sheet propose the same cuts. It changes nothing; loudness is the waveform peak times the mix envelope, so mute and solo are already in the answer |
| `set_playhead {t}` | moves the playhead and seeks the preview |
| `set_range {start?, end?}` | the in/out range (I / O / ⌥X); no bounds clears it |
| `set_selection {clips?}` | the timeline selection (a click); no clips clears it |
| `undo` · `redo` | one step each (⌘Z / ⇧⌘Z), reporting the step's name |
| `render_frame {t, max_width?}` | **the verification hook** |
| `export {preset, path, size?, range?, video_bitrate?, audio_bitrate?}` | writes a file and waits for it; `preset` is the encoding, `size` a Size-popup row (`document`, `1080p`, …) or `[width, height]`, default the document's size (a GIF or APNG's cap); `range: "in_out"` scopes it to the in/out range; the bitrates are the sheet's Quality popup in bits per second |

`set_range`, `set_selection`, `undo` and `redo` exist so that spec §10's own
verifications —
"every op is one undo step and undo restores the frame", "the in/out range
scopes the export" — can be checked by driving the built app, which is how
this project is verified.

Every tool takes an optional `project` (the path `get_project` reports); with
it omitted the call goes to the frontmost open document.

`render_frame` is what end-to-end checking is built on: it renders through the
same `AVComposition` + `AVVideoComposition` + Metal compositor an export uses,
so the PNG it returns is what the file would contain at that moment rather
than a second opinion about it. The frame comes back **both** as a base64 PNG
in an MCP image block, so a model can look at it, and as a file on disk whose
path the accompanying text names, so a script can diff it.

Times everywhere are **ticks at 600 000 per second** (spec §5.1), the unit the
model itself uses; every time argument is rounded to the project's frame grid
before it reaches an op. Clip, track, marker and media ids share one number
space, so an id names a thing unambiguously on its own.

Every tool call runs against the open documents through the same
`ProjectDocument` entry points the UI uses, so an agent edit is undoable,
dirties the document, and appears in the window immediately. Failures are
reported in band (`isError: true`) with a message naming the fix — an unknown
key, a refused overlap, a media clip an op needs — so a model can correct
itself instead of seeing a transport error.

## Architecture notes

- **Rust decides, AVFoundation and Metal do.** No pixel or sample work happens
  in Rust and there is no ffmpeg dependency: the core owns the model, the ops,
  the composition plan and the per-frame recipe; the platform decodes,
  composites and encodes.
- The FFI surface (`core/include/reelcut_core.h`) is an opaque, **immutable**
  `RcProject` handle. Every operation is pure — it returns a new handle and
  never mutates its input — which makes undo a stack of handles and makes
  publishing a handle to the compositor's queue safe. Complex data crosses as
  UTF-8 JSON, which is also what gives the MCP agent the same vocabulary the
  app has.
- `rc_project_apply` returns NULL two distinguishable ways: with `err_out`
  untouched it means "valid, but changes nothing" (register no undo step), and
  with `err_out` set it means the arguments were wrong. Getting that
  distinction wrong is a phantom undo step.
- Swift wraps the handle in `ReelProject`, whose `deinit` frees the Rust
  allocation; every `char *` the library returns is released with
  `rc_string_free`.
- The preview and the export share exactly one description of the movie. A
  frame that differs between them would be a bug in the compositor or the
  builder, never in a second rendering path — because there is not one.
