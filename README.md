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
- **Screen recording.** File ▸ New Recording… (⌥⌘N, or the welcome window's
  third button) opens a small floating panel: a display or a window (the
  system picker), a microphone with a live meter, system audio, click rings,
  30 or 60 fps, point or pixel size, and where it lands — a new project, or
  an open document at its playhead. A 3-2-1 countdown, then a red dot with
  the elapsed time in the menu bar carries Stop. The file is written to
  `~/Movies/Reelcut Recordings/` and imported as ordinary media (undo
  removes the clip, never the file); a microphone is a second file on its
  own Microphone track, aligned to the picture. A new project takes the
  rate you chose; a screen recording's own rate is whatever the screen did.
  The app asks for the Screen Recording and Microphone grants the first
  time you press Record, and never from an agent.
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
- **Sound.** The four sample-level audio properties — pan, mix to mono, a
  compressor and noise reduction — run in one processing tap per composition
  audio track, and the preview and the export share it. **Normalize** (the
  Volume section's button, Clip ▸ Normalize) sets a clip's volume so its own
  loudest moment lands at −1 dBFS, measured from the waveform cache over the
  part of the file that actually plays; it replaces the volume rather than
  multiplying it, so pressing it twice changes nothing. A two-channel
  **level meter** in the timeline bar shows the mix while it plays — peak
  over RMS, with a clip cell — computed as the tap's own measurement times
  the mix envelope, which is the same rule Remove Silences uses. And an
  export can be **normalised to a loudness target**: BS.1770-4 integrated
  loudness and true peak, measured on a first pass over the real mix, then
  one gain (no limiter) capped so the true peak stays under −1 dBTP. Every
  export reports what its sound measured, normalised or not.
- **Looks.** Every layer has a **blend mode** — normal, multiply, screen,
  add, overlay, darken, lighten, difference — in the Transform section
  beside Opacity, and it works on any kind of clip: a shape card over a
  screen recording is a tint, a screened white blob is a glow. A blend
  needs something UNDER it, so the section says so when there is nothing
  there (over the empty black canvas multiply reads black and screen
  changes nothing), and **Clip ▸ Add Background** is the answer: a plate on
  a new back-most track, a colour or an image, running the timeline's
  length. **Clip ▸ Add Blurred Background** is the screencast move — the
  selected clip copied behind itself, blown up to fill the canvas and
  blurred, playing exactly the same frames because it keeps the same source
  window, and muted so the mix does not play the recording twice. Shapes
  can be filled with a **gradient** instead of a flat colour, linear or
  radial, up to eight stops, at any angle. And a filter can be
  **animated**: an action's end state carries the filter stack, so a blur
  can ramp up across a clip like any other property.
- **Output.** **File ▸ Save Frame…** (⌥⌘E) writes the frame under the
  playhead as a PNG, JPEG or HEIC still — the same writer `render_frame`
  uses, so a still saved from the menu and one an agent asked for are the
  same file. PNG and HEIC keep the canvas's alpha; JPEG cannot, so it
  flattens onto black and the panel says so as you pick the format.
  **ProRes 4444** exports a real alpha channel, which is what a transparent
  canvas is for: set the background's opacity in the Document tab and the
  note there names the rows that can keep it (ProRes 4444 and APNG; a GIF
  can only be transparent or not, with nothing in between). **Burn in
  timecode** draws the document's own timecode over the picture, in the
  document's own spelling, on an export or a rendered frame — and it reads
  PROJECT time even in a file written from the in/out range, which is the
  number a note about that frame needs. The export sheet **remembers what
  you last chose** and saves **named presets** of it — a preset is the row
  of controls you picked, not the numbers they resolved to, so one saved on
  a 1080p document exports 4K at the right rate when you apply it to a 4K
  one. And **Window ▸ Export Queue** lines exports up and runs them one at a
  time: a queued job holds the timeline as it was when you confirmed it, so
  you can keep editing, undo, or close the document while it writes.
- **Inside a nest.** Double-click a nest clip, or **Clip ▸ Open Nest** (⌘↓),
  and the timeline, the canvas and the inspector all show what is inside it;
  ⌘↑ comes back out, and a breadcrumb at the left of the ruler says where you
  are. Every edit works in there — trim, slip, split, a property, a new
  clip — because an op now carries a **scope** naming the nest, and the core
  applies it to a view in which that nest's clips ARE the timeline. Entering
  and leaving are not undo steps; each edit is exactly one. The round trip
  (⇧⌘G, edit, ⌘G) still works and is still the way to change a nest's own
  frame. Three things stay the document's, and say so if you ask for them
  inside a nest: markers, the canvas, and the media list.
- **Viewing and finding.** **View ▸ Preview Quality ▸** Full / Half / Quarter
  draws the PREVIEW at a fraction of the canvas and lets the layer scale it
  back up — the export and a rendered frame never see the setting, so what
  you ship is unchanged whatever you are watching. **View ▸ Preview Window**
  (⇧⌘P) puts a second, chrome-free picture in its own window for a second
  display; it is the same player, not a second one, so the two can never
  drift apart. And the **Media tab** now finds things: a search field, a sort
  (import order, name, duration, kind), an **Unused only** switch, and
  **Reveal in Timeline** on a file's context menu, which selects the clips
  that use it and scrolls to them. "Used" counts clips inside a nest, which
  is also what Remove now asks before it refuses.
- **Playback** over an `AVComposition` built from the core's composition plan,
  with a Metal compositor drawing every frame from the core's frame recipe.
  A property-only edit re-renders the paused frame without rebuilding the
  player (the plan JSON is compared as a string).
- **Export** through an `AVAssetWriter` over the same composition, the
  format (H.264, HEVC, ProRes 422, ProRes 4444, M4A, WAV, AIFF, GIF, APNG)
  and the size chosen separately and both resolved by the core — the default
  size is the document's own, or for a GIF or APNG the format's cap fitted to
  it — and an optional loudness target and timecode burn-in over it, plus an
  offline single-frame render used for verification and by File ▸ Save Frame….
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
`designs/reelcut-roadmap-2.md`'s phases 0 through 7 have landed — the
groundwork, the cutting moves, clip identity, the screencast trio, captions
in both directions with the built-in text animations, sound (the mono fold,
a level meter, Normalize Clip, loudness on export and the two uncompressed
audio formats), looks (blend modes, gradient fills, the two background
commands and filters as animation targets), output (Save Frame…, ProRes 4444
with a real alpha channel, the timecode burn-in, remembered and named export
settings, and the export queue), viewing and finding (preview quality, a
second preview window, and a Media tab you can search, sort and filter), and
now the last of them: editing INSIDE a nest, which the spec designed and left
and which every op reaches through one envelope key.
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
| `ReelCore.swift` · `ReelOps.swift` | the FFI and the op vocabulary: `ReelCore.swift` is the **only** `rc_*` caller (`ReelProject` — handle + lazy snapshot — `ReelTime`, `ReelSnap`, `ReelExport`, `RecipeSource`, and the op-argument types), `ReelOps.swift` holds `ReelOp` and the typed op builders |
| `ProjectSnapshot.swift` | the `Codable` mirror of the §5.2 project JSON, the plan and the recipe, plus the §5.3 placement maths |
| `ProjectDocument.swift` | NSDocument, `.reelcut` package read/write, and the single mutation point (`applyEdit`, the live-edit trio, undo as a handle stack) |
| `MediaImporter.swift` | `AVURLAsset` probing (the one file allowed `async`/`await`), thumbnails, waveform peaks |
| `CompositionBuilder.swift` · `Compositor.swift` · `LayerRenderers.swift` · `LayerRenderersText.swift` · `Playback.swift` | plan → `AVComposition`; the `AVVideoCompositing` Metal pipeline — five states from three fragment functions, one of them reading the destination so a layer can blend; text/shape/image textures, a shape's gradient and the three text reveals the recipe asks for; the player and its rebuild-vs-refresh rule |
| `CaptionImporter.swift` · `CaptionLayout.swift` · `Transcriber.swift` · `CaptionExporter.swift` | captions in and out: the SubRip grammar, the placement every producer shares, on-device speech recognition and the cue builder over it, and the `.srt` / `.vtt` writer |
| `Exporter.swift` · `ExporterSettings.swift` · `ExporterWriter.swift` · `ExportSheetController.swift` (with `ExportSheetOptions` `ExportSheetResolve` `ExportSheetPresets` `ExportProgressSheetController`) | writing a file — two passes wherever it holds sound, the first measuring loudness — and rendering one frame offline; the sheet's controls, the resolution behind them and the progress sheet |
| `FrameWriter.swift` · `EditorViewController+SaveFrame.swift` | one composed frame to a PNG, JPEG or HEIC — a value type with no AppKit in it, called by File ▸ Save Frame… and by `render_frame` alike — and the panel that picks the URL |
| `ExportPresetsStore.swift` · `ExportQueueController.swift` · `ExportQueueWindowController.swift` · `AppSupport.swift` | the last export choice and the named presets as a value, the queue (one job at a time, each holding the timeline as it was enqueued) and its window, and the one spelling of `~/Library/Application Support/Reelcut/` |
| `AudioTap.swift` · `AudioDSP.swift` · `LevelMeter.swift` · `LevelMeterView.swift` | the sample-level audio the plan cannot carry (noise reduction, the compressor, the mono fold, the pan) and the level meter's model and its one view |
| `MediaPeaks.swift` · `AudioNormalize.swift` · `SilenceDetector.swift` | the waveform cache and the two questions asked of it: a clip's own peak (Normalize) and peak × envelope (the quiet spans) |
| `Loudness.swift` | BS.1770-4 integrated loudness and true peak, the export gain that follows, and the 16-bit scaler that applies it |
| `TimelineLayout.swift` · `TimelineSessions.swift` · `TimelineView.swift` | all tick↔point arithmetic; the gesture session structs; the timeline view |
| `CanvasSessions.swift` · `PreviewCanvasView.swift` · `EditorViewController+PreviewQuality.swift` · `PreviewWindowController.swift` | canvas geometry and gestures; the preview and its overlay; the preview's render size (View ▸ Preview Quality, applied to a copy of the player's composition so the export path cannot see it) and the second preview window, an `NSPanel` carrying a second layer on the same player |
| `InspectorPane.swift` · `InspectorViewController.swift` · `ClipPane` `MediaPane` `DocumentPane` (with `VideoPane` `AudioPane` `TextPane` `ShapePane` as section factories) | the binding that knows about actions, one file per tab, and the sections the Clip tab composes |
| `MediaRowView.swift` · `MediaListFilter.swift` · `MediaPaneCommands.swift` · `MediaUsage.swift` · `MediaReveal.swift` | the Media tab around its pane: the row and the drag it sources, the find band as a value, the row's commands, the one answer to "is this file used" (which walks the nests), and Reveal in Timeline |
| `EditorViewController.swift` + `EditorViewController+{Timeline,Canvas,Inspector,Export}.swift` | wiring in the base file, features in extensions |
| `AgentServer.swift` + `AgentServer+{Arguments,Project,Clips,Tracks,Media,Render,History,Silence,Captions,Audio,Background,Scope,Recording}.swift` · `AgentCatalog.swift` · `AgentCatalog+Clips.swift` · `AgentCatalog+Files.swift` | the MCP endpoint, its handlers, and the tool catalog |
| `RecordingSetup.swift` · `ScreenRecorder.swift` (with `+Finishing` and `+Content`) · `RecordingLanding.swift` · `ProjectDocument+Recording.swift` · `RecorderPanelController.swift` (with `+Rows` and `+Recording`) · `RecorderStatusItem.swift` · `AppDelegate+Recording.swift` · `AgentServer+Recording.swift` | screen recording (road map 3): the values, the session over ScreenCaptureKit and a second `AVCaptureSession` for the microphone, the landing as ordinary media, the floating non-activating panel with its countdown and meter, the menu-bar status item, and the `record_screen` tool |
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

**One tool per row of the op table** — what an op MEANS is spec §6 and the
module doc of `core/src/edit.rs`, and what it TAKES is `core/src/op_table.rs`,
which every op tool PRINTS rather than restates, so a tool's arguments are
the core's by construction and only its prose is the app's. Same name, same
argument names — and each of them also takes **`scope`**, a nest id, which
applies that one op inside that nest (`core/src/scope.rs`). Seven refuse it
by name, because they have
no meaning in there: the three marker ops, `set_canvas` and the three media
ops. And a scoped op can fail where an unscoped one cannot, which is worth
knowing before reading a result: the clip and track caps and the nesting
depth are document-wide and invisible from inside a nest, so an op that is
perfectly valid against the nest still comes back "too many clips" or "nests
are more than 8 deep". The ops themselves:
`add_clip`, `add_text_clip`, `add_shape_clip`, `add_background`,
`add_blurred_background`, `insert_clip`,
`overwrite_clip`, `move_clip`, `trim_start`, `trim_end`, `rate_stretch`,
`slip`, `roll`, `split`, `delete`, `ripple_delete`, `ripple_delete_range`,
`ripple_delete_ranges`, `lift_range`, `insert_time`, `close_gap`,
`set_speed`, `set_reversed`,
`freeze_frame`, `detach_audio`, `duplicate`, `paste`, `paste_attributes`,
`nest`, `unnest`, `set_video`, `set_audio`, `set_text`, `set_shape`,
`set_clip`, `set_enabled`,
`set_transition`, `set_transition_duration`, `add_transition`,
`set_transition_style`, the four action ops and
`add_zoom_action` beside them, and the
track, marker, canvas and media ops — plus the app-state tools below. The
count of each is `rc_op_names`' length and the catalog's, and the startup
parity check compares them, so it is one number in the code and not one
here.

**A `patch` argument is your own object, and the core reads it.** It merges
key by key at every depth — a nested object keeps the keys you left out, a
key set to `null` clears it, an array replaces its whole list — and an
unknown key or a misspelt value at any depth is an error naming the dotted
path to it and the value you sent (`filters[1].kindd`), never a different
edit made quietly. Nothing is corrected or clamped on the way: a colour is
four numbers, `[r, g, b, a]`, each 0–1 — `video.chroma.key`, which names a
hue rather than paints with it, is the one `[r, g, b]` in the model.

| Tool | |
|---|---|
| `open_project {path}` | a `.reelcut` package, or any movie/sound/picture, which opens as a new untitled project around it |
| `new_project {path?}` | a blank 1920×1080 / 30 fps project, saved straight away when given a path |
| `save_project {path?}` | returns once the package is really on disk |
| `get_project` | the whole §5.2 JSON, plus the playhead, selection and in/out range that live only in the app |
| `import_media {path}` | probes a file and returns the **new media id**; `add_clip` then places it |
| `import_captions {path, track?}` | an SRT file as text clips (File ▸ Import Captions…) |
| `consolidate_media {}` | copies every referenced file into the package (File ▸ Consolidate Media…) |
| `record_screen {seconds, display?, window?, microphone?, system_audio?, show_clicks?, rate?, size?, place?, path?}` | records a display (index, 0 = main) or a window (a `CGWindowID`) for `seconds` and lands it as a clip at the target document's playhead — or as an untitled document rated at `rate` when nothing is open (File ▸ New Recording…). `microphone` records the default microphone to a second file on a Microphone track; `path` is a FOLDER override. It reads the two grants and never asks: the refusal names the System Settings pane, and a shell-launched instance runs under its TERMINAL's grants |
| `transcribe {clips?, language?, place?}` | on-device speech recognition into caption clips (File ▸ Generate Captions…). Returns the cues in ticks whether or not it places them, and `place: false` changes nothing at all. macOS gates speech recognition and this tool never asks: without the grant it refuses with the status named, since the system prompt needs a frontmost app and an agent-driven one never is |
| `export_captions {track?, path, format?}` | one text track out as `.srt` or `.vtt` (File ▸ Export Captions…). The track is never guessed — with no all-text track, or more than one, it refuses and lists the candidates |
| `detect_silence {clips?, threshold_db?, min_length?, padding?}` | the quiet spans of the timeline, which `ripple_delete_ranges` then cuts — the same detector Clip ▸ Remove Silences… uses, so an agent and the sheet propose the same cuts. It changes nothing; loudness is the waveform peak times the mix envelope, so mute and solo are already in the answer |
| `normalize_clip {clips, peak_db?}` | sets each clip's volume so its own loudest moment lands at `peak_db` (default −1 dBFS) — the Volume section's Normalize button and Clip ▸ Normalize. Measured from the waveform cache over the part that plays, so it knows nothing about the volume, fades, ducking, mute or solo already on the clip; it replaces the volume rather than multiplying it, writes the clip's base level even inside an action, and leaves `muted` alone. One gain per clip, one undo step, and what it could not measure comes back under `skipped` |
| `set_playhead {t}` | moves the playhead and seeks the preview |
| `set_range {start?, end?}` | the in/out range (I / O / ⌥X); no bounds clears it |
| `set_selection {clips?}` | the timeline selection (a click); no clips clears it |
| `set_scope {nest?, clip?}` | opens a nest to look and edit inside it — the mirror of double-clicking a nest clip and of Clip ▸ Open Nest (⌘↓). At most one argument, and NEITHER means the timeline: send it with no arguments to come back out. `clip` is the precise spelling, since one nest can be shown by two clips at two different starts. With a nest open `get_project` lists ITS clips, `render_frame` draws it at its own frozen size, and every op lands inside it — the same view a person gets. Every op tool also takes `scope` directly, which names a nest for one call and outranks whatever is open |
| `undo` · `redo` | one step each (⌘Z / ⇧⌘Z), reporting the step's name |
| `render_frame {t, max_width?, path?, format?, burn_in_timecode?}` | **the verification hook**. With neither `path` nor `format` it writes a PNG to a temporary file, exactly the call it always was. `format` is `png`, `jpeg` or `heic` and WINS over the path's extension, which is replaced rather than appended to (`{path: "shot.jpg", format: "png"}` writes `shot.png`); `png` and `heic` keep the canvas's alpha and `jpeg` flattens onto black. It is the same writer File ▸ Save Frame… uses, so a still from the menu and one from here are byte-identical. `burn_in_timecode` draws the document's timecode over the picture — the only way a burn-in can be photographed |
| `export {preset, path, size?, range?, video_bitrate?, audio_bitrate?, loudness_lufs?, peak_dbtp?, burn_in_timecode?}` | writes a file and waits for it; `preset` is the encoding, `size` a Size-popup row (`document`, `1080p`, …) or `[width, height]`, default the document's size (a GIF or APNG's cap); `range: "in_out"` scopes it to the in/out range; the bitrates are the sheet's Quality popup in bits per second; `loudness_lufs` normalises the whole mix by one gain to that integrated target and `peak_dbtp` is the ceiling that gain is capped against (a ceiling with no target is refused — there would be nothing to cap). `burn_in_timecode` draws the document's own timecode over every frame (the export sheet's checkbox), showing PROJECT time even in a file written from the in/out range. The result reports what the file's sound MEASURED, asked for or not, and echoes the burn-in either way |

`set_range`, `set_selection`, `set_scope`, `undo` and `redo` exist so that
spec §10's own verifications —
"every op is one undo step and undo restores the frame", "the in/out range
scopes the export", "an edit inside a nest lands inside it" — can be checked
by driving the built app, which is how this project is verified.

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

An edit that did not happen says which of the two it was. **An identity** —
the project already says what you asked — reports that it made no change and
names no rule, so there is nothing to go looking for. **A refusal** is a rule
declining the edit, and the reply carries that rule's own sentence naming the
op and the values you can act on: which track is locked, which clips still
show the media, by how many ticks two clips would overlap and how long the
shorter one is, and the argument that would let the call through
(`with_clips: true`, `ripple: true`). Neither leaves an undo step, so a call
that did not land is safe to retry.

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
- `rc_project_apply` returns NULL three distinguishable ways: with neither
  message set it means "valid, but nothing needed to change"; with
  `reason_out` set a rule refused the edit and that is the rule's own
  sentence; with `err_out` set the arguments were wrong. The first two
  register no undo step — getting that distinction wrong is a phantom undo
  step — and only the third is an error.
- Swift wraps the handle in `ReelProject`, whose `deinit` frees the Rust
  allocation; every `char *` the library returns is released with
  `rc_string_free`.
- The preview and the export share exactly one description of the movie. A
  frame that differs between them would be a bug in the compositor or the
  builder, never in a second rendering path — because there is not one.
