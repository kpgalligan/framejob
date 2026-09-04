# Reelcut — design proposal

**Status: proposal, nothing built.** Sibling of `~/devel/rasterize`: the same
shape (Swift/AppKit app over a Rust staticlib core, a hand-maintained C
header as the one contract, xcodegen, an embedded MCP agent), a different
domain.

## 1. What this is

a screencast editor's editor without a screencast editor's recorder. Open one or more video
files from disk, arrange them on layered tracks over a fixed canvas, trim,
split, annotate, animate, and export. Mac only, Apple Silicon, macOS 15+.

The bar is a screencast editor's balance: enough to make a real cut with text,
shapes, transitions and simple animation, without Final Cut's magnetic
timeline, roles, multicam, scopes, or a plugin ecosystem.

Deliberate non-goals: screen or camera recording, multicam, color grading
beyond per-clip controls, audio beyond volume/fade/duck, a plugin system,
any platform but macOS.

## 2. The a screencast editor model, and why it stays simple

Six ideas do most of the work. Reelcut copies all six.

1. **One kind of track.** Every track holds any clip — video, audio,
   still, text, shape. There are no video-vs-audio track types; an
   audio-only clip simply draws a waveform. Higher track = in front.
2. **A fixed canvas with direct manipulation.** The document has a size
   (1920×1080 by default). Clips are placed on it by dragging on the
   preview; scale, position, rotation and crop are clip properties with
   numbers in the inspector and handles on the canvas.
3. **Actions, not keyframes.** An Action is a span on a clip with an
   easing curve. You edit the property values at the *end* of the span;
   the values at the start are whatever was already in effect. There is
   no keyframe graph.
4. **Overlap is a transition.** Sliding one clip over its neighbour on
   the same track makes a transition of that length. No transition
   track, no browser to drag from.
5. **One inspector, tabbed by what the selection is.** Video / Audio /
   Text / Shape for the selected clip; Media and Document always.
6. **A small keyboard vocabulary.** ⌘T split, W/E trim to playhead,
   ⌘⌫ ripple delete, ⇧⌘F freeze frame, M marker, Space/JKL transport.

Dropped from a screencast editor: everything that only makes sense for a recording
it made itself (mouse/keyboard/touch callouts, pointer effects), templates,
publishing to YouTube/Vimeo, the stock-media library.

## 3. Window layout

```
┌────────────────────────────────────────────────────────────────────────────────┐
│ ⏮ ◀◀ ▶ ▶▶ ⏭ ↻   00:00:20:12 / 00:01:00:00   [Fit ▾] [Safe]      [T] [▭▾] [M] [Export] │
├───────────────────────────────────────────────────────┬────────────────────────┤
│                                                       │ Video Audio Text Shape │
│      ┌─────────────────────────────────────────┐      │ Media Document         │
│      │ Reelcut — intro title                   │      │────────────────────────│
│      │                                         │      │ ▾ Transform            │
│      │                                         │      │   Scale    ──o──  100 %│
│      │            (screen recording)           │      │   Position x 480 y 270 │
│      │                                     ──▶ │      │   Rotation        0 °  │
│      │                           ┌────────┐    │      │   Opacity  ────o  100 %│
│      │                           │ webcam ○┼   │      │ ▸ Crop                 │
│      │                           └────────┘    │      │ ▸ Corner radius        │
│      └─────────────────────────────────────────┘      │ ▸ Shadow               │
│        1920 × 1080 · 30 fps                           │ ▸ Color                │
│                                                       │ ▸ Chroma key           │
│                                                       │ ▸ Speed                │
│                                                       │ ▸ Actions              │
├───────────────────────────────────────────────────────┴────────────────────────┤
│ [Split ⌘T] [Ripple ⌘⌫] [Marker M] [Snap ●]                zoom ──o── [Fit] ▤ │
│          ┆0:00      0:10   ▼  0:20      0:30      0:40      0:50      1:00     │
│ Track 4  ┆ [Intro title ▒▒▒▒]           [Arrow ▒]                              │
│ Track 3  ┆ [Webcam.mov ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓]                          │
│ Track 2  ┆ [Screen recording.mov ████████████████████████████][xf][B-roll ████]│
│ Track 1  ┆ [Music.m4a ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]   │
└────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Default | Range | Holds |
|---|---|---|---|
| Toolbar | 44 pt | fixed | transport, timecode, canvas zoom, safe guides, add text/shape/marker, export |
| Preview canvas | flexible | — | the composition at canvas size, letterboxed in the void |
| Inspector | 320 pt | 280–440, collapsible (⌥⌘I) | tab strip + collapsible sections |
| Timeline | 240 pt | 140 pt – 60 % of window | its own toolbar row, ruler, track headers + lanes |

Inspector and timeline are `NSSplitView` panes; sizes persist. There is no
left panel: the media library is an inspector tab, as in a screencast editor, so the
canvas gets the width.

## 4. The regions in detail

### 4.1 Toolbar

- **Transport**: go to start, previous edit point, play/pause, next edit
  point, go to end, loop.
- **Timecode** in the mono face: current time, then duration, in the
  document's frame rate (`00:00:20:12 / 00:01:00:00`). Click to type a
  time; accepts `1:23`, `83.5`, `1:23:04`. A Document setting switches
  frames to milliseconds.
- **Canvas zoom** popup (Fit, 50, 100, 200 %) and a title-safe /
  action-safe guide toggle.
- **Add Text** (T), **Add Shape** menu (rectangle, ellipse, line, arrow),
  **Add Marker** (M), **Export…** (⌘E).

Snapping lives in the timeline toolbar because it is a timeline concern.

### 4.2 Preview canvas

- The composition at document size, centered in the void
  (`DS.canvasVoid`) with a 24 pt margin; the canvas background is the
  document's background color. Zoom with ⌘= / ⌘- / ⌘0 (fit) or pinch;
  Space-drag pans when zoomed in.
- Shows the frame at the playhead. During playback the frames come from
  the player; while scrubbing or editing, from exact seeks.
- **Selection**: click picks the topmost visible clip under the cursor at
  the current time (locked tracks are not hit). ⇧-click extends. Clicking
  empty canvas clears.
- **Handles** on the selected clip, drawn in canvas space through the
  clip's scale and rotation: eight scale handles (corners keep aspect,
  ⇧ frees it; edges scale one axis), a rotation handle above the top
  edge, drag inside to move, ⌥ scales about the center. Arrow keys nudge
  1 px, ⇧-arrows 10 px.
- **Crop mode** (C, or double-click a video clip): the handles become
  crop edges in source space; the uncropped source ghosts at 30 %.
  Esc or Return leaves.
- **Text** clips edit inline on double-click (an `NSTextView` overlay
  positioned in canvas space). Line and arrow shapes have endpoint
  handles.
- **Snapping** while dragging: canvas center lines, edges, thirds, and
  other visible clips' edges and centers. Guides draw while snapped;
  ⌘ suppresses.
- The overlay draws in the same coordinate space as the video by mapping
  through the player layer's `videoRect`, so handles and pixels never
  drift apart.
- Canvas drags go through the document's `beginLiveEdit` /
  `updateLiveEdit` / `endLiveEdit` trio (rasterize's pattern): inspector
  fields update live, the player's composition is not rebuilt until the
  gesture ends.

### 4.3 Inspector

Tab strip across the top: **Video, Audio, Text, Shape, Media, Document.**
A tab is disabled when no selected clip has that aspect. Selecting a clip
switches to the most relevant enabled tab unless the user pinned one.
Multiple selected clips edit their common properties together.

Sections are disclosure groups with a reset-to-default in the header.
Controls are the rasterize `OptionControls` family: slider + field pairs
with quick-value chevrons, color wells, steppers.

**Video** — any clip with pixels. Text and shape clips get Transform,
Opacity and Shadow only.

- *Transform*: Scale % (1–1000), Position X / Y in canvas pixels (origin
  at canvas center, X right, Y down), Rotation °, Opacity %. Buttons:
  Fit to canvas, Fill canvas.
- *Crop*: left / top / right / bottom in source pixels; a "Crop on
  canvas" button enters crop mode.
- *Corner radius* px, applied to the cropped rectangle before rotation.
- *Shadow*: on/off, color, opacity, blur, angle, distance.
- *Color*: brightness, contrast, saturation, hue rotate; Reset.
- *Speed*: rate ×0.1 – ×10 with presets (0.5, 1, 2, 4), "Keep pitch",
  the resulting duration. Reverse is M3 (see §9).
- *Actions*: table of the clip's actions (start, duration, curve, which
  properties change); Add Action at the playhead, Remove, curve popup.
  While the playhead is inside an action, edits in this tab set that
  action's end state and the section header says so.
- M3: *Chroma key* (key color with a canvas eyedropper, tolerance,
  softness, spill suppression), *Reflection*, *Filters* (blur, sharpen,
  pixelate, sepia, noir, vignette, invert — Core Image behind them).

**Audio** — clips with an audio track.

- Volume % (0–400, dB shown), Mute.
- Fade in / fade out in seconds (also the corner handles on the clip).
- Ducking: "lower other audio to N % while this clip has sound", with
  attack / release. Realised as volume ramps folded into the other clips'
  envelopes by the core.
- Mix to mono. Detach Audio (button; also Clip menu).
- Volume actions share the Actions table.
- M3: pan, Smooth volume levels (compressor), Remove background noise.

**Text**

- Content (multi-line), font family / style / size, color, alignment
  (left / center / right and top / middle / bottom within the box), line
  spacing, letter spacing.
- Outline (width, color); Backdrop (fill, opacity, padding, corner
  radius); Shadow (shared section).
- Box: auto-size, or fixed width with wrapping.
- Presets: Title, Subtitle, Lower third, Caption — set face, size,
  backdrop and position in one click.
- Animation is Actions on position / opacity / scale. Built-in text
  animations (typewriter, per-word fade) are M3.

**Shape**

- Kind: rectangle, rounded rectangle, ellipse, line, arrow. Stroke width
  and color, fill color and opacity, arrowheads at start / end, corner
  radius, Shadow.
- M3: *Spotlight* — darkens the canvas outside a rectangle or ellipse,
  with optional 1.2–2× zoom of the region. The stand-in for a screencast editor's
  freehand callout that works on any footage.

**Media**

- Every imported file: thumbnail, name, duration, dimensions, fps, an
  audio badge, a "missing" badge. Add Media… button; drag files from the
  Finder onto the panel, the canvas, or the timeline.
- Drag from the list to a timeline track (drops at the cursor) or onto
  the canvas (appends on a new top track at the playhead).
- Right-click: Reveal in Finder, Relink…, Remove (refuses while in use and
  offers "Remove and delete its clips").
- Files are referenced through security-scoped bookmarks, never copied.
  File > Consolidate Media… copies them into the package (M3).

**Document**

- Canvas size: presets (1080p, 4K, 720p, 1080×1920 vertical, 1080×1080
  square, 2560×1440, source size) or custom; a "resize clips
  proportionally" toggle when changing.
- Frame rate: 24, 25, 30, 50, 60, 23.976, 29.97, or "match first clip".
- Background color. Duration read-out. Timecode format (frames vs ms).
- Markers list: rename, jump, delete, chapter toggle. Chapter markers
  export as chapter metadata.

### 4.4 Timeline

A toolbar row, the ruler, then the lanes. Track headers (120 pt) on the
left scroll vertically with the lanes; ruler and lanes scroll horizontally
together.

**Toolbar row**: Split (⌘T), Trim Start (W), Trim End (E), Ripple Delete
(⌘⌫), Add Marker (M), Snap toggle (N), zoom slider with Fit (⇧Z), track
height (S / M / L).

**Ruler**: adaptive ticks (frames → seconds → 10 s → minutes as you zoom).
The playhead head is a coral triangle you drag to scrub; clicking the
ruler moves the playhead. I / O set an in/out range at the playhead
(shaded on the ruler and lanes, ⌥X clears); the range scopes playback
loops, ripple-delete-range, and export. Markers are small flags, chapter
markers filled; double-click to rename; drag to move.

**Tracks**: header shows the name (double-click to rename), eye (hide
video), speaker (mute), lock. Top track is front-most. Drag a header to
reorder. Dragging a clip above the top track or below the bottom one
creates a track; Track > Remove Empty Tracks cleans up.

**Clips** are 4 pt-rounded bars. Name label top-left; a filmstrip of
thumbnails on video clips; waveform on the lower half of a video clip
with audio, or the whole bar of an audio clip. Tint by kind: video slate,
audio green, still violet, text amber, shape teal, nest grey. Selected:
coral outline. Locked track: hatched overlay. Muted: waveform at 40 %.
An action is a darker band along the top edge over its span with a curve
glyph. A transition is a hatched overlap zone labelled with its name.
Fade handles are small squares at the audio corners you drag inward.

**Gestures**

- Drag a clip body: moves in time; vertical movement changes track;
  snaps to clip edges, the playhead, markers and the in/out points (⌘
  suppresses). ⌥-drag duplicates.
- Drag a clip edge: trims. A front trim keeps later content in place
  (source-in and timeline-start move together). Trimming stops at the
  source's ends; stills, text and shapes have no source bound.
- ⌥-drag an edge: rate-stretch — speed changes so the content fills the
  new length.
- Overlapping a neighbour on the same track makes a transition (default
  Cross Dissolve). Clips never push each other.
- Marquee-select on an empty lane; ⇧-click adds; ⌘A selects all; ⌥⌘A
  selects everything after the playhead (then drag to insert time).
- ⌘T splits the selected clips at the playhead, or every unlocked clip
  under the playhead when nothing is selected.
- W / E trim the selected clip's start / end to the playhead.
- ⌫ deletes and leaves a gap. ⌘⌫ ripple-deletes: removes the clip(s) and
  shifts everything later on every unlocked track left by the removed
  span. With an in/out range and no selection it removes the range from
  the whole timeline — the "cut this bit out" move.
- ⇧⌘F freeze frame: splits the clip under the playhead and inserts a 2 s
  still of that frame.
- Detach Audio: the clip's audio becomes its own clip on the track below
  (created if needed); the video clip goes silent.
- Transitions: double-click the overlap (or the Transition section that
  appears in the Video tab) for type — Cross Dissolve, Fade through
  black / white, Push (4 directions), Wipe, Slide, Zoom — and duration.
  Changing the duration moves the later clip to match.
- Nest (⌘G): selected clips collapse into one clip; double-click enters
  it with a breadcrumb. M3.
- Auto-scroll follows the playhead during playback; pinch and ⌘= / ⌘-
  zoom about the cursor; ⇧Z fits the whole timeline.

## 5. Editing model

**Time.** Integer ticks at 600 000 per second — a timescale that divides
every common frame duration exactly: 24, 25, 30, 48, 50, 60, 120 fps and
the 24000/1001 and 30000/1001 rates. Edits snap to the document's frame
grid; sources keep their own rate and the compositor picks the nearest
source frame. Timecode formatting and parsing are core functions so the
app and the agent agree.

**Project** — the Rust value. Small, and it holds no pixels.

- `canvas`: width, height, fps (rational), background color.
- `media[]`: id, bookmark/path, kind, duration, dimensions, fps, has
  audio / video, has alpha.
- `tracks[]`: id, name, hidden, muted, locked. Index 0 is the back track
  (rasterize's bottom-first order); the UI draws it last.
- `clips[]`: id, track, `start`, `duration`, `source`, `speed`, video
  props, audio props, text props, shape props, `actions[]`,
  `transition_in`.
  - `source` is one of `Media {media, in}`, `Still {media, at}` (freeze
    frame), `Image {media}`, `Text`, `Shape`, `Nest {project}`.
- `markers[]`: time, name, color, is_chapter.
- **Not** in the model: selection, playhead, zoom, scroll, panel sizes.
  That is view state and lives in Swift.

**Actions.** `Action { start (clip time), duration, curve, end: Patch }`.
To evaluate a property at clip time *t*: start from the clip's base
props, apply the end patch of every action that finished before *t*, and
if *t* is inside an action, interpolate from that state to the action's
end patch along its curve (linear, ease in, ease out, ease in-out). Video,
audio and text properties all go through the one list with typed patches.
Splitting a clip keeps each action with the correct half; trimming clamps.

**Purity and undo.** Every edit is `fn(&Project, args) -> Option<Project>`
— `None` means nothing would change, so no phantom undo step. The Swift
document keeps a stack of handles; `NSUndoManager` records the previous
one. Because the value holds no pixels, this is cheaper than rasterize's
equivalent.

**Persistence.** `.reelcut` is a package: `project.json` (versioned; the
reader accepts every prior version, the writer enforces the reader's
caps), `cache/` (thumbnails and waveform peaks — regenerable, ignored by
version control), `media/` (only after Consolidate). NSDocument autosave.

## 6. Architecture — Rust decides, AVFoundation and Metal do

All pixel and sample work happens on the platform. Pure-Rust decoding of
H.264 / HEVC / ProRes does not exist at production quality, and linking
ffmpeg is a 60 MB dependency with licensing questions and no VideoToolbox
by default. AVFoundation gives hardware decode and encode, synchronized
audio/video playback, scrubbing, and export for free.

Everything that *decides* what to show is Rust and testable without a GPU
or a video file: the model, every edit, the evaluation of the timeline at
a time, the plan for playback and export, the file format, the agent
server.

The seam is two Rust products:

1. **Composition plan** — for the whole timeline. Per track, a list of
   segments (media, source range, timeline range, speed), with
   overlapping clips assigned to alternating A/B composition tracks; a
   list of instruction ranges (spans where the set of active layers is
   constant); per-segment audio envelopes as piecewise-linear volume
   ramps with fades, ducking and volume actions already folded in. Swift
   turns this into `AVMutableComposition` + `AVMutableAudioMix` +
   `AVMutableVideoComposition` whenever the *structure* changes.
2. **Frame recipe** — for one time *t*. The ordered list of layers to
   draw with fully resolved properties: source composition-track id or a
   text/shape description, source time, crop, transform, radius, opacity,
   shadow, color, key, and for a transition the partner layer and
   progress. The custom `AVVideoCompositing` asks for this per frame and
   renders it with Metal. A property-only edit (a slider drag) changes
   only recipes, so nothing is rebuilt.

```
   AppKit UI ──edit(args)──▶ Project (immutable) ──evaluate──▶ Composition plan ──▶ AVMutableComposition
   (timeline, canvas,        ▲ undo = old handle               Frame recipe(t)          + AudioMix + VideoComposition
    inspector, agent)        │                                      │                          │
                             │                                      ▼                          ▼
                             └──────── new handle ◀───    Metal compositor ◀── decoded frames ── AVPlayer / AVAssetExportSession
                                                          (AVVideoCompositing)
                                                                │
                                                                ▼
                                                        screen / .mp4 .mov
```

**Rust crate `reelcut_core`** (staticlib + rlib, `rc_` prefix, opaque
`RcProject`):

| Module | Owns |
|---|---|
| `model.rs` | the types above, serde derive |
| `time.rs` | ticks, frame snapping, timecode format / parse |
| `edit_clip.rs` / `edit_track.rs` / `edit_time.rs` | pure ops in their own `impl Project` blocks: move, trim, split, speed, freeze, detach, properties; track add/remove/reorder/flags; ripple, insert time, range delete |
| `actions.rs` | action evaluation and interpolation |
| `transition.rs` | overlap detection, transition params, progress at *t* |
| `evaluate.rs` | `frame_recipe(t)`, `composition_plan()` |
| `audio.rs` | envelopes; ducking from peak arrays the host extracts |
| `snap.rs` | snap candidates and nearest-within-threshold resolution |
| `format.rs` | `.reelcut` JSON, `RC_FORMAT_VERSION`, migrations |
| `export.rs` | presets → concrete settings, chapter list |
| `agent.rs` | the MCP server, copied from rasterize (it is generic) |
| `ffi_*.rs` + `include/reelcut_core.h` | thin shims; the header is the contract |

Tests are black-box in `core/tests/`, through the FFI, against oracles:
split then rejoin is the identity; ripple preserves every relative gap on
unlocked tracks; a recipe is continuous across an action boundary; a
plan's instruction ranges tile the timeline with no overlap.

**Swift app**:

| File | Owns |
|---|---|
| `ReelCore.swift` | the **only** `rc_*` caller; `ReelProject` handle wrapper with `deinit` free |
| `ProjectDocument.swift` | NSDocument, package read/write, the single mutation point (`applyEdit`, live-edit trio), undo as handle stack |
| `Playback.swift` | `AVPlayer` over the plan; debounced rebuilds; coalesced exact seeks; `preferredMaximumResolution` = canvas size for preview |
| `Compositor.swift` | the `AVVideoCompositing` implementation; one Metal pass per layer (crop, transform, radius, shadow, opacity, color, key in one fragment shader with a uniform block), one two-texture pass per transition |
| `LayerRenderers.swift` | text (Core Text) and shapes (Core Graphics) to textures, cached by description hash — rasterize's "described layer" rule: the recipe carries the description, never pixels |
| `MediaImporter.swift` | `AVURLAsset` probing, thumbnails (`AVAssetImageGenerator`), waveform peaks (`AVAssetReader` + vDSP), background + cached in the package |
| `Exporter.swift` | `AVAssetExportSession` over the same composition; presets from the core; chapter metadata; progress sheet |
| `TimelineView.swift` | custom `NSView`; drawing plus gesture sessions (`ClipDragSession`, `TrimSession`, `RangeSession`) as structs |
| `PreviewCanvasView.swift` | `AVPlayerLayer` under a transparent overlay view for handles and guides |
| `InspectorViewController.swift` + `VideoPane` / `AudioPane` / `TextPane` / `ShapePane` / `MediaPane` / `DocumentPane` | one file per tab |
| `AgentServer.swift` / `AgentCatalog.swift` | MCP mirrors of every edit, plus `render_frame` (PNG of the canvas at *t*) as the verification hook |
| `Theme.swift` | rasterize's `DS` tokens and the same three vendored faces |

**Performance budget**: the compositor renders a 1080p frame in under
8 ms (60 fps with headroom); preview decodes at canvas size, export at
full; seeks are coalesced; thumbnails and peaks are generated off the
main thread once and cached.

## 7. Repo layout and conventions

```
reelcut/
  Makefile            # app / test / lint / typecheck / project / run — rasterize's
  project.yml         # xcodegen; macOS 15, arm64; .reelcut UTI + movie/audio/image types
  core/               # reelcut_core (staticlib + rlib)
    Cargo.toml        # serde, serde_json, tiny_http
    include/reelcut_core.h
    src/  tests/
  app/
    Bridging/Reelcut-Bridging-Header.h
    Sources/          # AppKit, programmatic, no storyboards
    Resources/Fonts   # Source Sans 3, IBM Plex Mono, Darker Grotesque
  designs/            # this document
```

Carried over verbatim from rasterize: pure ops returning `Option`; the
three-file FFI lockstep (`ffi_*.rs` → header → `ReelCore.swift`);
`catch_unwind` + `err_out` on every export; the frozen-file / extension-
file rule; one document mutation point; no force unwraps; MCP parity for
every user-visible edit; `DS` tokens for all chrome.

## 8. Keyboard map

| Keys | Action |
|---|---|
| Space | Play / pause |
| J / K / L | Reverse / pause / forward; L again for 2×, 4× |
| ← / → | Previous / next frame (⇧: 10 frames) |
| ↑ / ↓ | Previous / next edit point |
| Home / End | Start / end |
| ⌘T | Split at playhead |
| W / E | Trim start / end to playhead |
| ⌫ | Delete, leave gap |
| ⌘⌫ | Ripple delete (selection, or the in/out range) |
| ⇧⌘F | Freeze frame |
| M | Add marker |
| I / O / ⌥X | Set in / set out / clear range |
| N | Toggle snapping |
| T | Add text clip at playhead |
| C | Crop mode on the selected clip |
| ⇧Z | Fit timeline |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit (canvas, or timeline when focused) |
| ⌘G / ⇧⌘G | Nest / un-nest (M3) |
| ⌘E | Export… |
| ⌥⌘I | Toggle inspector |
| ⌥-drag clip | Duplicate |
| ⌥-drag clip edge | Rate stretch |
| ⌘-drag | Suppress snapping |

## 9. Milestones

**M1 — Cut.** The point at which a screencast editor stops getting opened. Open a
file → a project at the source's size and rate; import more; tracks;
move / trim / split / delete / ripple; play, scrub, JKL; transform, crop
and opacity on the canvas and in the inspector; markers; save and open
`.reelcut`; undo; export H.264 and HEVC. The custom compositor ships here
with a single-layer path so the plumbing is proven before effects arrive.

**M2 — Compose.** Text, shapes, transitions, audio volume / fade / duck /
detach, freeze frame, speed, in/out range, chapters on export, the MCP
agent with parity for everything above.

**M3 — Polish.** Actions, corner radius / shadow / reflection, chroma key,
color controls, filters, nests, spotlight, GIF / APNG export, noise
removal, SRT captions (import and burn-in), Consolidate Media, ffmpeg-
assisted import.

## 10. Decisions and risks

- **AVFoundation, not ffmpeg.** Risk: MKV, WebM/VP9 and AV1-in-MKV do not
  open. Mitigation (M3): an opt-in import step that shells out to a
  user-installed ffmpeg (present at `/opt/homebrew/bin/ffmpeg` on this
  machine) to rewrap or transcode into the package.
- **Custom compositor from day one.** `AVVideoCompositing` has sharp edges
  (pixel-buffer pools, timing, the render-context change callback).
  Building the single-layer version in M1 de-risks every later effect.
- **Speed and pitch** come from `scaleTimeRange` and the time-pitch
  algorithm. Reverse is not native; M3 pre-renders reversed segments to a
  cache file.
- **Text and shapes are described, not rasterized, in the model** — the
  recipe carries the description; the platform renders it (Core Text /
  CG), exactly as rasterize's text layers work.
- **Time is 600 000 ticks/s.** Mixed source rates resolve at render, never
  in the model.
- **No left panel.** Media is an inspector tab. Revisit if libraries grow
  past a few dozen files.
