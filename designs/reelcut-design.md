# Reelcut — design and implementation spec

**Status: accepted design, nothing built yet.** This is the handoff document:
the implementer is expected to start from here with no other context. Sibling
of `~/devel/rasterize` — the same shape (Swift/AppKit app over a Rust
staticlib core, a hand-maintained C header as the one contract, xcodegen, an
embedded MCP agent), a different domain. Where this document says "as in
Rasterize" it names the file to copy from.

Reading order for an implementer: §1–2 (the product), §5–7 (model, ops,
architecture — the parts with exact schemas), §10 (build order), then §3–4
when building the UI, §8–9 for conventions and keys, §11 for the decisions
already made so they are not re-litigated.

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

**The opening flow is the point.** File > Open on a `.mov` or `.mp4` (or a
drop on the Dock icon, or the welcome window's Open Video…) creates an
*untitled* project sized to that file, with the file as the first clip on
Track 1, ready to cut. Save then writes a `.reelcut` package next to the
source. The app is also the Alternate handler for movie, audio and image
types so Open With… works from the Finder.

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
│      │ Intro title                             │      │────────────────────────│
│      │                                         │      │ ▾ Transform            │
│      │                                         │      │   Scale    ──o──  100 %│
│      │            (screen recording)           │      │   Position x 480 y 270 │
│      │                                     ──▶ │      │   Rotation        0 °  │
│      │                           ┌────────┐    │      │   Opacity  ────o  100 %│
│      │                           │ webcam ○┼   │      │ ▸ Crop                 │
│      │                           └────────┘    │      │ ▸ Corner radius        │
│      └─────────────────────────────────────────┘      │ ▸ Shadow               │
│        1920 × 1080 · 30 fps                           │ ▸ Color                │
│                                                       │ ▸ Speed                │
│                                                       │ ▸ Actions              │
│                                                       │ ▸ Transition           │
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

Inspector and timeline are `NSSplitView` panes; sizes persist in
`UserDefaults`. There is no left panel: the media library is an inspector
tab, as in a screencast editor, so the canvas gets the width. The window has a
welcome sibling (`WelcomeWindowController`, as in Rasterize) offering Open
Video…, New Project…, and Recent.

## 4. The regions in detail

### 4.1 Toolbar

- **Transport**: go to start, previous edit point, play/pause, next edit
  point, go to end, loop (loops the in/out range when set, else all).
- **Timecode** in the mono face: current time, then duration, in the
  document's frame rate (`00:00:20:12 / 00:01:00:00`). Click to type a
  time; accepts `1:23`, `83.5`, `1:23:04`. A Document setting switches
  frames to milliseconds. Formatting and parsing are core functions
  (`rc_timecode_format` / `rc_timecode_parse`).
- **Canvas zoom** popup (Fit, 50, 100, 200 %) and a title-safe /
  action-safe guide toggle (90 % and 80 % rectangles).
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
  the current time (locked or hidden tracks are not hit). ⇧-click
  extends. Clicking empty canvas clears. Hit-testing uses each layer's
  canvas rect (§5.3) rotated by its rotation.
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
  ⌘ suppresses. Candidates are computed in Swift from the layer rects;
  the nearest-within-threshold pick is `rc_snap_resolve`.
- The overlay draws in the same coordinate space as the video by mapping
  through the `AVPlayerLayer.videoRect`, so handles and pixels never
  drift apart.
- Canvas drags go through the document's `beginLiveEdit` /
  `updateLiveEdit` / `endLiveEdit` trio (Rasterize's pattern): inspector
  fields update live, the player's composition is not rebuilt until the
  gesture ends (§7.6).

### 4.3 Inspector

Tab strip across the top: **Video, Audio, Text, Shape, Media, Document.**
A tab is disabled when no selected clip has that aspect. Selecting a clip
switches to the most relevant enabled tab unless the user pinned one.
Multiple selected clips edit their common properties together (one op
with several clip ids).

Sections are disclosure groups with a reset-to-default in the header.
Controls are Rasterize's `OptionControls` family: slider + field pairs
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
  **Reverse**, a "Reversed frames" readout, a Render Reverse button, and
  the resulting duration. Reverse (M3) is a checkbox over `set_reversed`,
  but unlike everything else in this tab it does not change the picture by
  itself: AVFoundation cannot play a clip backwards, so the frames are
  pre-rendered once per media file (§11, §5.6) and the composition reads
  that file instead. Ticking the box therefore starts a render behind a
  progress sheet with a Cancel — and **until the frames exist the clip
  draws the missing-media slate, never forward frames**, because a clip
  that silently played the wrong way was the whole defect the pre-render
  fixes. The readout says which state the clip is in (Rendered, Rendering…,
  Not rendered, Media missing); Render Reverse is live only in the "Not
  rendered" state, which is what a cancelled or failed render leaves
  behind. Nothing retries on its own: a render the user stopped must not
  restart itself on the next keystroke.
- *Actions*: table of the clip's actions (start, duration, curve, which
  properties change); Add Action at the playhead (⌥⌘K), Remove, curve
  popup. While the playhead is inside an action, edits in this tab set
  that action's end state and the section header says so.
- *Transition* appears when the clip overlaps its predecessor: kind and
  duration.
- M3: *Chroma key* (key color with a canvas eyedropper, tolerance,
  softness, spill suppression), *Reflection*, *Filters* (blur, sharpen,
  pixelate, sepia, noir, vignette, invert — Core Image behind them).
- M3: *Spotlight* — the stand-in for a screencast editor's freehand callout — lives
  here rather than in the Shape pane below, because only the layer that
  owns the pixels can draw its 1.2–2× zoom.

**Audio** — clips whose media has an audio track and whose audio is
enabled.

- Volume % (0–400, dB shown), Mute.
- Fade in / fade out in seconds (also the corner handles on the clip).
- Ducking: "lower other audio to N % while this clip plays", with
  attack / release. a screencast editor's rule: for the whole clip extent, not
  voice activity. Realised as volume ramps folded into the other clips'
  envelopes by the core.
- Mix to mono. Detach Audio (⌥⌘D; also Clip menu).
- Volume actions share the Actions table.
- M3 — Pan, "Smooth volume levels" (compressor), "Remove background
  noise". Unlike everything above, these three cannot be a gain curve, so
  they are not folded into the core's envelope: they are sample work, done
  in Swift by one `MTAudioProcessingTap` per composition audio track, and
  the SAME tap serves the preview and the export (the mix reaches both
  `AVPlayerItem.audioMix` and `AVAssetReaderAudioMixOutput.audioMix`, and
  taps were measured to run on each). A track no clip of which uses them
  gets no tap and is bit-identical to before they existed.
  - Pan is a balance: one gain per channel, constant power across the
    sweep and unity at the centre, so 0 is exactly a bypass and a hard
    pan is +3 dB in the channel it goes to. Inaudible on a clip whose
    source is mono — the widening to stereo happens after the tap.
  - The compressor is a channel-strip insert on the track, ahead of the
    fader: its envelope carries across a cut and the volume, fades and
    ducking apply after it. Its attack and release are ticks in the
    schema but sub-frame, and the pane shows them in ms.
  - Noise reduction is a short-time spectral attenuator over a noise
    floor tracked from the clip itself — not a gate, and it delays the
    track it runs on by 512 samples (10.7 ms at 48 kHz).
  - Read at the clip's BASE properties, never through an action, exactly
    as ducking is (§7.2).

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
- M3: *Spotlight* — which darkens the canvas outside a rectangle or
  ellipse, with an optional 1.2–2× zoom of the region — is a
  `video.spotlight` prop and appears in the **Video** pane, not here.

**Media**

- Every imported file: thumbnail, name, duration, dimensions, fps, an
  audio badge, a "missing" badge. Add Media… (⇧⌘I); drag files from the
  Finder onto the panel, the canvas, or the timeline.
- Drag from the list to a timeline track (drops at the cursor) or onto
  the canvas (appends on a new top track at the playhead).
- Right-click: Reveal in Finder, Relink…, Remove (refuses while in use and
  offers "Remove and delete its clips").
- Files are referenced (path + `URL.bookmarkData()`; the app is not
  sandboxed, so no security scope), never copied. File ▸ Consolidate
  Media… — and the pane's own Consolidate… button — copies them into the
  package and relinks the project at the copies, with a progress sheet and
  a Cancel; §5.6 has the rules it follows.
- File ▸ Import Captions… reads a SubRip (`.srt`) file and lays it out as
  text clips in the Caption preset on a track of their own, which is what
  makes burn-in on export free: a caption is an ordinary text clip, so it
  retimes, restyles and renders like one. Malformed entries are reported
  with their line numbers rather than skipped in silence.

**Document**

- Canvas size: presets (1080p, 4K, 720p, 1080×1920 vertical, 1080×1080
  square, 2560×1440, source size) or custom; a "resize clips
  proportionally" toggle when changing.
- Frame rate: 24, 25, 30, 50, 60, 23.976, 29.97, or "match first clip".
- Background color. Duration read-out. Timecode format (frames vs ms).
- "Fit new clips to canvas" (default on): a dropped clip larger than the
  canvas gets Fit scale.
- Markers list: rename, jump, delete, chapter toggle. Chapter markers
  export as a chapter track (M2, `AVAssetWriter` path).

### 4.4 Timeline

A toolbar row, the ruler, then the lanes. Track headers (120 pt) on the
left scroll vertically with the lanes; ruler and lanes scroll horizontally
together (one `NSScrollView` whose document view draws everything; the
header column and ruler are floating subviews pinned in `scroll(_:)`).

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
creates a track; Track > Remove Empty Tracks cleans up. New Track is ⇧⌘N.

**Clips** are 4 pt-rounded bars. Name label top-left; a filmstrip of
thumbnails on video clips; waveform on the lower half of a video clip
with audio, or the whole bar of an audio clip. Tint by kind: video slate,
audio green, still violet, text amber, shape teal, nest grey. Selected:
coral outline. Locked track: hatched overlay. Muted: waveform at 40 %.
An action is a darker band along the top edge over its span. A transition
is a hatched overlap zone labelled with its kind. Fade handles are small
squares at the audio corners you drag inward.

**Gestures** (exact op semantics in §6)

- Drag a clip body: moves in time; vertical movement changes track;
  snaps to clip edges, the playhead, markers and the in/out points (⌘
  suppresses). ⌥-drag duplicates. A drop the core refuses (§6, overlap
  rule) animates back.
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
- ⌫ deletes and leaves a gap. ⌘⌫ ripple-deletes.
- ⇧⌘F freeze frame at the playhead.
- Detach Audio (⌥⌘D).
- Transitions: double-click the overlap (or the Transition section) for
  kind — Cross Dissolve, Fade through black / white, Push (4 directions),
  Wipe, Slide, Zoom — and duration. Changing the duration moves the later
  clip to match.
- Nest (⌘G): the selected clips collapse into one grey clip standing for
  the group, which then moves, trims, fades and transforms as one thing;
  the new clip is selected. Un-nest (⇧⌘G) opens every nest clip in the
  selection and selects what came out, in one undo step. **Entering a
  nest** — double-click it, the timeline and canvas show its contents, a
  breadcrumb leads back out — is NOT built, and waits on the op table:
  every clip argument in §6 resolves against the project's own `clips`
  (`Project::clip`), so no op can name a clip inside a nest, and an
  inside view could only be read-only. Naming one needs a path-valued
  `clip` argument or a nest scope on the envelope — the core already has
  the shape, `Instance::path`. Until then the round trip is the way in:
  ⇧⌘G, edit, ⌘G, which is the identity on clip content but drops the
  nest clip's own group-level properties.
- Auto-scroll follows the playhead during playback; pinch and ⌘= / ⌘-
  zoom about the cursor; ⇧Z fits the whole timeline.

## 5. Editing model

### 5.1 Time

Integer ticks at **600 000 per second** (`Ticks = i64`, `TIMESCALE =
600_000`) — a timescale that divides every common frame duration exactly:
24, 25, 30, 48, 50, 60, 120 fps and the 24000/1001 and 30000/1001 rates
(a 29.97 frame is 20 020 ticks, a 23.976 frame 25 025). `CMTime` at
timescale 600 000 round-trips exactly. Edits snap to the document's frame
grid (`rc_time_snap_to_frame`, round-to-nearest); sources keep their own
rate and AVFoundation picks the source frame. Frame rates are rationals
`[num, den]` everywhere.

### 5.2 Project — the JSON schema (format version 2)

The Rust value, serialized by serde. Small, no pixels. All times are
ticks, all positions canvas pixels, colors `[r, g, b, a]` floats 0–1,
angles degrees, opacity/volume 0–1 (volume may exceed 1, up to 4).

```json
{
  "version": 2,
  "canvas": { "width": 1920, "height": 1080, "fps": [30, 1],
              "background": [0, 0, 0, 1], "fit_new_clips": true,
              "timecode_frames": true },
  "media": [
    { "id": 1, "path": "/Users/…/talk.mov", "bookmark": "<base64 or null>",
      "kind": "video", "duration": 36000000, "width": 1920, "height": 1080,
      "fps": [30000, 1001], "has_video": true, "has_audio": true,
      "has_alpha": false }
  ],
  "tracks": [
    { "id": 1, "name": "Track 1", "hidden": false, "muted": false, "locked": false }
  ],
  "clips": [
    { "id": 17, "track": 1, "start": 0, "duration": 12000000,
      "source": { "kind": "media", "media": 1, "in": 3000000, "reversed": false },
      "enabled": { "video": true, "audio": true },
      "speed": 1.0,
      "video": { "x": 0, "y": 0, "scale": 1.0, "rotation": 0, "opacity": 1,
                 "crop": { "l": 0, "t": 0, "r": 0, "b": 0 },
                 "corner_radius": 0,
                 "shadow": null,
                 "color": { "brightness": 0, "contrast": 0, "saturation": 0, "hue": 0 },
                 "chroma": null,
                 "filters": [], "reflection": null, "spotlight": null },
      "audio": { "volume": 1.0, "muted": false, "fade_in": 0, "fade_out": 0,
                 "duck": null, "mono": false, "keep_pitch": true,
                 "pan": 0, "compressor": null, "noise_reduction": 0 },
      "text": null, "shape": null,
      "actions": [
        { "id": 1, "start": 2400000, "duration": 900000, "curve": "ease_in_out",
          "end": { "video": { "scale": 0.6, "x": 520 } } }
      ],
      "transition_in": null }
  ],
  "markers": [ { "id": 1, "time": 6000000, "name": "Intro", "color": "red", "chapter": true } ],
  "next_id": 18,
  "nests": []
}
```

- `source.kind` is one of `media` (video/audio file, with `in` = source
  time of the clip's first frame and `reversed` = play it back to front),
  `still` (`media`, `at` — a freeze frame), `image` (`media` — a
  PNG/JPEG/HEIC), `text`, `shape`, `nest` (`project` — the ID of an entry
  in the project's `nests[]`, M3). `speed` applies to `media` only;
  `still`, `image`, `text`, `shape` and `nest` have no source bound and
  any duration.
- `source.reversed` (M3) is a fact, not an instruction: the core does no
  pixel work, so it changes neither the plan nor the recipe, and Swift
  substitutes a pre-rendered reversed asset for that media's segments
  (§11). `in` is then measured in the reversed stream, which is the same
  length — so an `in` of 0 is the media's last frame, and every time
  computation in the core is unchanged.
- `enabled.video` / `enabled.audio` — Detach Audio flips them across two
  clips (§6). A media clip with `has_audio` false has `audio: null`.
- `video.shadow`: `{ "color": [...], "opacity": 0.5, "blur": 12, "angle": 315, "distance": 8 }`.
- `video.chroma` (M3): `{ "key": [r,g,b], "tolerance": 0.2, "softness": 0.1, "spill": 0.5 }`.
- `video.filters` (M3): an ordered list of `{ "kind": …, "amount": 0..1 }`,
  at most **four** — a shader budget, not taste: the uniform block carries
  four (kind, amount) pairs. `kind` ∈ `blur`, `sharpen`, `pixelate`,
  `sepia`, `noir`, `vignette`, `invert`. They are a pass of the one Metal
  pipeline (§7.5), not Core Image: a second renderer would be a second
  thing for export to disagree with.
- `video.reflection` (M3): `null` or `{ "opacity": 0.35, "height": 0.5,
  "gap": 0, "falloff": 1.0 }`. `height` and `falloff` are fractions of the
  layer's cropped height so a reflection survives a scale change; `gap` is
  source pixels.
- `video.spotlight` (M3): `null` or `{ "shape": "rect" | "ellipse",
  "x": 0, "y": 0, "width": 480, "height": 270, "feather": 40, "dim": 0.6,
  "zoom": 1.0 }` — darkens the canvas outside the region and magnifies
  what is inside it (1–2×). Centre and box are SOURCE pixels from the
  cropped rect's centre. A *video* prop, not a shape one (§4.3's Shape
  pane first listed it): only the layer that owns the pixels can draw the
  zoom.
- `audio.duck`: `{ "level": 0.2, "attack": 300000, "release": 600000 }`.
- `audio.pan` (M3) is -1 (hard left) to +1 (hard right);
  `audio.noise_reduction` (M3) is 0 (off) to 1.
- `audio.compressor` (M3): `null` or `{ "threshold_db": -18, "ratio": 3,
  "attack": 6000, "release": 120000, "makeup_db": 0 }` — "smooth volume
  levels". Unlike ducking, this cannot be expressed as a gain curve, so
  the model carries the parameters and the DSP is Swift's.
- `text`: `{ "content": "…", "font": "SourceSans3-SemiBold", "size": 72, "color": [...],
  "align": "center", "valign": "middle", "line_spacing": 1.0, "tracking": 0,
  "outline": null | { "width": 2, "color": [...] },
  "backdrop": null | { "color": [...], "padding": 12, "radius": 8 },
  "width": null | 800 }`.
- `shape`: `{ "kind": "arrow", "width": 320, "height": 120,
  "stroke": { "width": 6, "color": [...] }, "fill": null | [...],
  "arrow_start": false, "arrow_end": true, "radius": 0,
  "from": [0, 1], "to": [1, 0] }` — `from`/`to` are unit coordinates in the
  box, for line and arrow only.
- `actions[].end` is a patch: any subset of `video`, `audio`, `text` keys.
  `curve` ∈ `linear`, `ease_in`, `ease_out`, `ease_in_out`.
- `transition_in`: `null` or `{ "kind": "cross_dissolve" | "fade_black" |
  "fade_white" | "push_left" | "push_right" | "push_up" | "push_down" |
  "wipe" | "slide" | "zoom" }`. Its duration *is* the overlap with the
  previous clip on the track; a clip with no overlap ignores it.
- `nests` (M3) holds the groups every `nest` clip points at:
  `{ "id": 60, "name": "Intro", "width": 1920, "height": 1080,
  "tracks": [...], "clips": [...] }`. A nest is **not** a nested project:
  its tracks and clips live in the parent's one id space, reference the
  parent's `media[]`, and start from 0 — so the plan's clip-keyed track
  map, `CompositionBuilder`'s media lookup and `next_id` all keep working
  when a nest is flattened at evaluation time. Its `width`/`height` are
  frozen at the size the parent had when it was made, so a later canvas
  change does not silently re-lay-out a nest. A nest's duration is the
  largest clip end inside it; the nest CLIP's duration is independent and
  trims it. Nesting is capped at **8** levels, a nest may not reach
  itself, and nested tracks and clips count toward the same caps as the
  timeline's.
- Ids are unique across all kinds in one project (`next_id`) — INCLUDING
  everything inside a nest — so an MCP call can name anything by one
  integer.
- **Not** in the model: selection, playhead, zoom, scroll, panel sizes.
  That is view state and lives in Swift.

### 5.3 Placement semantics

- The layer's *uncropped* source rectangle (media pixel size; a text or
  shape box's size) is placed with its center at `(canvas_center + (x, y))`,
  scaled by `scale`, rotated by `rotation` about that center. Then `crop`
  removes edges **in place** — cropping never shifts content (a screencast editor's
  behaviour). `corner_radius` rounds the cropped rectangle, in source
  pixels, before rotation.
- Scale 1 = native pixels. A 4K clip on a 1080p canvas overflows at scale
  1; Fit scale is `min(cw/sw, ch/sh)`, Fill is `max`. New clips get Fit
  when `fit_new_clips` is on and the source exceeds the canvas.
- The canvas rect of a layer (for hit-testing, handles, snapping) is
  therefore computable from the clip and the source size alone. For text,
  the size is the measured layout size; only the platform knows it, so
  `LayerRenderers` reports it to the overlay (a cache keyed by the text
  description hash) — the model never stores it.
- **`spotlight` is in that same source-pixel frame** (M3): its centre is
  measured from the centre of the *cropped* rect, and its `width`,
  `height` and `feather` are source pixels — like `corner_radius` and
  `crop`, and unlike `x`/`y`, which are canvas pixels. So a spotlight
  stays on the face it was put on when the layer is scaled, moved or
  rotated, and the compositor scales all four by the layer's scale on the
  way to canvas space.
- **`reflection` hangs below the layer** (M3), mirrored about the cropped
  rect's bottom edge, `gap` source pixels clear of it, `height` of the
  layer's cropped height tall, fading out with `falloff`. It is drawn
  BEFORE the layer, so the layer always wins where they meet, and it is
  part of the layer — it rotates with it.
- **A nest's layers are flattened at evaluation time** (M3): each drawing
  clip inside a nest becomes one recipe layer with the nest clip's
  transform folded in (scales multiply, rotations add, offsets rotate),
  and every such layer carries the nest's canvas rect as its `clip_rect`
  (§7.3). Fold and clip are both similarity transforms, so the
  composition is exact and no intermediate render target is needed.

### 5.4 Actions

`Action { start (clip time), duration, curve, end: Patch }`. To evaluate a
property at clip time *t*: start from the clip's base props, apply the end
patch of every action that finished at or before *t* (in start order),
then if *t* is inside an action, interpolate from that state to the
action's end patch along its curve. Numeric fields interpolate; colors
interpolate per channel; booleans and strings switch at the end. Actions
on a clip may not overlap (`add_action` refuses). Video, audio and text
properties all go through the one list with typed patches.

An action's end patch is deliberately **lenient** — `set_action_end` merges
whatever it is given, so a half-written animation stays editable — while
`set_video` and its siblings are **strict** and name an out-of-range value.
The evaluator is therefore the last line of defence: `frame_recipe` and
`clip_state` clamp every value they produce to the same table the ops
enforce (opacity 0–1, scale 0.01–10, gain 0–4, non-negative radii and
crops) and collapse a NaN to that field's neutral value. The compositor
never has to defend itself, and one bad number cannot blank a frame.

### 5.5 Purity and undo

Every edit is `fn(&Project, args) -> Option<Project>` — `None` means
nothing would change, so no phantom undo step; invalid arguments are an
`Err(String)` at the FFI (`err_out`), never a panic. The Swift document
keeps a stack of handles; `NSUndoManager` records the previous one
(`ImageDocument.swift` in Rasterize is the template — `applyEdit`,
`beginLiveEdit`/`updateLiveEdit`/`endLiveEdit`, `countEditChange`,
`registerUndo` nowhere else). Because the value holds no pixels this is
cheaper than Rasterize's equivalent.

### 5.6 Persistence

`.reelcut` is a package (UTI `com.kgalligan.reelcut-project`, conforms to
`com.apple.package`), read and written through NSDocument `FileWrapper`s:

```
Talk.reelcut/
  project.json          # §5.2; RC_FORMAT_VERSION bumps on any schema change
  cache/                # regenerable; never required to open
    thumbs/<media id>/<index>.jpg
    peaks/<media id>.bin        # f32 max-magnitude per bucket, 100 buckets/s
    reversed/<media id>-<digest>.mov   # pre-rendered reverse (M3)
  media/                # only after Consolidate (M3)
```

The reader accepts every prior version; the writer enforces the reader's
caps (max 4096 clips, 64 tracks, 1024 markers — `RC_CAPS` in
`format.rs`). Opening a project whose media is missing opens anyway with
the clips marked missing (rendered as a slate) and Relink… offered.

**Consolidate Media** (File ▸ Consolidate Media…, and the Media tab's own
button) fills `media/`: every file the project references is copied in and
its media entry relinked at the copy, so the package becomes the whole edit
and survives the footage being moved or deleted. The rules, all of which
`MediaConsolidator` enforces:

- An untitled project has no package, so the command offers the Save that
  makes one rather than inventing a destination — a cache written to the
  temporary directory is regenerable, media put there would be lost.
- Names are made unique inside `media/` (`intro.mov`, `intro-2.mov`), and
  two entries resolving to one file share one copy.
- A file already inside `media/` is never copied onto itself; its entry is
  still relinked, because a stale bookmark outranks the path in
  `mediaURL(for:)`.
- **Bookmarks are cleared** for a consolidated entry: a save writes a new
  package beside the old one and swaps, so a bookmark INTO the package is a
  bookmark to a file a later save replaces. The path is the durable half,
  and opening a package re-anchors any media it cannot find at
  `<package>/media/<same name>` — which is what lets a consolidated package
  be moved or renamed.
- Nothing is relinked until its copy is on disk, so a failure or a Cancel
  part-way leaves the rest pointing at the originals and the project still
  opens.

**Reversed assets** (`cache/reversed/`) are the one cache entry that is
expensive rather than cheap to rebuild, and the choice of where to keep them
is deliberate. `set_reversed` changes no pixels in the core (§6, §11), so
Swift pre-renders the media backwards once and the composition substitutes
that file for the clip's segments; a ten-minute 4K reverse is minutes of
decode and encode. `cache/` is still the right home: it satisfies the rule
above — delete it and `ReverseRenderer` makes it again from media the project
still references — and it travels with the package, so a project handed to
someone else arrives with its reversed clips ready. That is the opposite of
the call §11 makes for ffmpeg rewraps, and for the opposite reason: a rewrap
is the only *decodable* copy of footage, so losing it loses the media, while
a reverse is a rendering of media that is still there. An untitled document
renders into the same temporary cache directory the filmstrips use, and the
first save copies it in.

The file name carries a digest of the source's path, size and modification
second, exactly as a rewrap's does, because a media *id* outlives the file
behind it: Relink… can point media 3 at another movie, and a reverse named
for the id alone would then be frames of the wrong film. The digest makes a
render both reusable and self-invalidating; the previous digest's file is
deleted when a new one lands. A reverse is written to a `.partial` sibling
and moved into place only on success, so a cancel can never leave a
half-reversed file that later looks finished. Rendering it means creating a
directory inside the package, so `ProjectDocument.packageContentsDidChangeOnDisk()`
is called afterwards for the reason Consolidate calls it.

`fileWrapper(ofType:)` is a whitelist of `project.json`, `cache/` and
`media/`: a directory not named there is DELETED by the next save.

## 6. Edit operations — exact semantics

All ops take clip/track/marker *ids*. All time arguments are snapped to
the frame grid first. "Refuses" = returns `None` at the FFI (the UI beeps
or animates back); "error" = `Err`.

**Clips**

| Op | Semantics |
|---|---|
| `add_clip {track, media, at}` | Whole media as one clip at `at`; source in 0; Fit scale if `fit_new_clips` and the source exceeds the canvas. Refuses if the overlap rule fails. |
| `add_text_clip {track, at, duration=5 s, text?}` / `add_shape_clip {…, shape?}` | Same placement rules; default text is the Title preset centered, default shape the rectangle — except that `shape.kind = "arrow"` is created with `arrow_end` on, since an arrow with no head is a diagonal line. `text` and `shape` are **patch objects** in the `set_text` / `set_shape` shape, merged over that default — not a bare string or kind — so an explicit `arrow_end: false` still wins. (The MCP tools additionally accept a bare string as shorthand: the words for `text`, a kind name for `shape`.) |
| `move_clip {clips, delta, track}` | Shifts by `delta` ticks (may be negative; clamps at 0) and optionally to another track (all selected clips keep their relative track offsets). **Overlap rule** on the destination track: a clip may overlap at most one neighbour on each side, and each overlap must be ≤ half of the shorter of the two clips; anything else refuses. An overlap is a transition; a clip that gains a predecessor overlap gets `transition_in = cross_dissolve` if it had none. |
| `trim_start {clip, to}` | New start `to`; source in advances by `(to − start) × speed`. Clamps: `to ≥ start − in/speed` (source bound), `to < end − one frame`. |
| `trim_end {clip, to}` | New end `to`; clamps to the source's remaining length (`media` sources) and `> start`. |
| `rate_stretch {clip, to_end}` | `speed = source_len / (to_end − start)`; duration follows. Media sources only — a non-media clip is an **error**, not a refusal, so an MCP caller gets a message it can correct from (the UI never offers it). |
| `split {clips?, at}` | Two clips. Second: `start = at`, `in += (at − start) × speed`, base props = the evaluated state at `at`. Actions before `at` stay with the first; after go to the second (start rebased); a straddling action becomes two — the first half's end patch is the evaluated state at `at`. `transition_in` stays with the first. Refuses when `at` is not strictly inside. **Omitting** `clips` — not passing a flag — means every unlocked clip `at` is strictly inside, the ⌘T-with-no-selection case. |
| `delete {clips}` | Removes; gaps stay. |
| `ripple_delete {clips}` / `ripple_delete_range {from, to}` | Removes; then for each removed span (union of the removed clips' spans, processed right-to-left) shifts every clip on **unlocked** tracks whose start ≥ span end left by the span length. Clips on other tracks that straddle a span are left in place. Range form: every unlocked clip is split at both bounds first, the middle pieces removed, then the shift. |
| `insert_time {at, length}` | Shifts every unlocked clip whose start ≥ `at` right by `length`. Straddling clips are left in place. |
| `set_speed {clip, rate, keep_pitch}` | `duration = source_len / rate`; actions keep their clip-relative *fraction* of the clip. Media sources only, an **error** on any other kind (as `rate_stretch`). Rate is clamped to ×0.1–×10. |
| `set_reversed {clip, reversed}` | Plays the media back to front, or forward again. The core does no pixel work, so this changes neither the plan nor the recipe: Swift substitutes a pre-rendered reversed asset for that media's segments (§11). `in` is measured in the direction the clip PLAYS, so reversing keeps the in point and therefore shows different frames; the alternative would put two conventions into every trim and split. Media sources only, an **error** on any other kind. |
| `freeze_frame {clip, at, duration=2 s}` | `split` at `at`, `insert_time(at, duration)`, then a `still {media, at: source time}` clip filling the gap on the same track with the original's video props. Media sources only, an **error** on any other kind (as `rate_stretch`). |
| `detach_audio {clip}` | `enabled.audio = false` on the clip; a new clip with `enabled = {video: false, audio: true}`, same source/in/duration/speed and the audio props, on the track below (a track is inserted at index 0 if needed). Refuses if the media has no audio or audio is already detached. |
| `duplicate {clips}` | Copies placed after the originals' span on the same tracks (⌥-drag then moves them). |
| `paste {at, track?, payload}` | Inserts the clips of a clipboard payload — `{"clips": [...], "media": [...]}`, what ⌘C wrote to `com.kgalligan.reelcut.clips` — with fresh ids for the clips, their actions and any media row added. The EARLIEST clip lands exactly at `at` and the rest keep their offsets from it. A payload clip's `track` is a **depth from the front** (0 = front-most), not an id, since the ids belong to the document copied from: `track` names where depth 0 lands (default: the front-most track), the rest follow by the same index delta, and tracks missing behind it are added. Media is matched to `media[]` **by path** — reused when it is there, appended when it is not — so a paste between documents brings the entry with it. A clip the overlap rule refuses on its target track goes on a new track in front (as Add Text does, §4.1), so the only refusal is an empty clip list; a malformed payload is an **error**. |
| `nest {clips, name?}` | Collapses the selection into ONE clip showing a nest (§5.2), on the front-most track the selection occupied, running from the earliest start to the latest end. The clips move whole — ids, props, actions, transitions — keeping their relative times (the earliest starts at 0 inside) and their track order, onto fresh tracks of the nest's own that copy the source tracks' names and their hidden/muted/locked state. The nest's canvas is frozen at the project's current size, so a later `set_canvas` cannot re-lay-out what is inside it. Media is untouched: a nest references the project's `media[]` in the same one id space. Refuses on an empty selection, on a selection of one nest clip, and when the nest clip would break the overlap rule against what was left behind. |
| `unnest {clip}` | The inverse: the nest's clips return at `clip.start + their own start` with fresh ids (as `split` then a re-join mints fresh ones), on tracks counted back from the nest clip's own — the nest's front-most track lands where the nest clip was — with tracks missing behind added, and the nest clip goes. A clip the overlap rule refuses lands on a new track in front, as `paste` does, so a group can always be opened. A nest clip trimmed shorter than its contents gives **all** of them back: there is no in point on a nest, so this is the inverse of `nest`, not of the trim. The nest is dropped from `nests[]` when no clip anywhere still shows it. An **error** when `clip` is not a nest clip. |
| `set_video {clips, patch}` / `set_audio` / `set_text` / `set_shape` | Merge the patch into the base props. Refuses if nothing changes. |
| `set_enabled {clip, video?, audio?}` | Visibility/mute per clip. |
| `set_transition {clip, kind|null}` | Sets `transition_in`. `set_transition_duration {clip, duration}` moves the clip so the overlap equals `duration` (subject to the overlap rule). |

**Actions**

| Op | Semantics |
|---|---|
| `add_action {clip, at, duration=1 s}` | Refuses if it would overlap another action or run past the clip end. End patch starts empty (= no change until edited). |
| `set_action {clip, action, start?, duration?, curve?}` | Same overlap checks. |
| `set_action_end {clip, action, patch}` | Merges into the end patch; a key set to `null` removes it. |
| `remove_action {clip, action}` | |

**Tracks, markers, canvas, media**

| Op | Semantics |
|---|---|
| `add_track {index, name?}` | Inserts (index 0 = back). |
| `remove_track {track, with_clips=false}` | Refuses on a non-empty track unless `with_clips`. |
| `move_track {track, index}` · `set_track {track, name?, hidden?, muted?, locked?}` | |
| `remove_empty_tracks` | |
| `add_marker {at, name?, chapter?, color?}` · `set_marker {marker, time?, name?, chapter?, color?}` · `remove_marker {marker}` | Markers snap to frames; two markers may not share a time. Default color `red`. |
| `set_canvas {width?, height?, fps?, background?, rescale_clips?, fit_new_clips?, timecode_frames?}` | `rescale_clips` multiplies every clip's `x`, `y`, `scale` by the size ratio. Changing fps re-snaps every clip start and duration. |
| `add_media {descriptor}` → returns the id · `relink_media {media, path, bookmark}` · `remove_media {media, with_clips=false}` | The descriptor is the `media[]` element minus `id`; the host probes the file. |

Every op is also an MCP tool with the same name and arguments (§7.9).

## 7. Architecture — Rust decides, AVFoundation and Metal do

All pixel and sample work happens on the platform. Pure-Rust decoding of
H.264 / HEVC / ProRes does not exist at production quality, and linking
ffmpeg is a 60 MB dependency with licensing questions and no VideoToolbox
by default. AVFoundation gives hardware decode and encode, synchronized
audio/video playback, scrubbing, and export for free.

Everything that *decides* what to show is Rust and testable without a GPU
or a video file: the model, every edit, the evaluation of the timeline at
a time, the plan for playback and export, the file format, the agent
server.

```
   AppKit UI ──apply(op json)──▶ Project (immutable) ──evaluate──▶ Composition plan ──▶ AVMutableComposition
   (timeline, canvas,           ▲ undo = old handle               Frame recipe(t)          + AudioMix + VideoComposition
    inspector, agent)           │                                      │                          │
                                │                                      ▼                          ▼
                                └──── new handle + snapshot ◀──  Metal compositor ◀── decoded frames ── AVPlayer / ExportWriter
                                                                 (AVVideoCompositing)
                                                                       │
                                                                       ▼
                                                               screen / .mp4 .mov
```

### 7.1 The FFI surface

`core/include/reelcut_core.h` is hand-maintained and is the contract.
Conventions are Rasterize's: opaque handles, every export wrapped in
`catch_unwind`, NULL-tolerant, errors through `char **err_out` freed with
`rc_string_free`, all returned strings freed with `rc_string_free`.
Complex data crosses as **UTF-8 JSON** — the project itself, ops, the
plan, the recipe — which keeps the header small and gives the MCP agent
the same vocabulary for free.

```c
typedef struct RcProject RcProject;

/* lifecycle */
RcProject *rc_project_new(uint32_t w, uint32_t h, uint32_t fps_num, uint32_t fps_den);
RcProject *rc_project_from_json(const char *json, char **err_out);   /* any prior format version */
char      *rc_project_to_json(const RcProject *p);                   /* current format version */
void       rc_project_free(RcProject *p);
void       rc_string_free(char *s);

/* edits — one entry point. `op` is {"op": "<name>", ...args} (§6).
 * Returns a NEW project; NULL with err_out untouched = the op would change
 * nothing (no undo step); NULL with err_out set = invalid op or arguments. */
RcProject *rc_project_apply(const RcProject *p, const char *op, char **err_out);

/* queries */
int64_t rc_project_duration(const RcProject *p);
char   *rc_project_composition_plan(const RcProject *p);              /* §7.2 */
char   *rc_project_frame_recipe(const RcProject *p, int64_t t);       /* §7.3 */
char   *rc_project_clip_state(const RcProject *p, uint32_t clip, int64_t t); /* evaluated props at t, for the inspector */
char   *rc_project_snap_candidates(const RcProject *p, const char *exclude_clips_json); /* sorted ticks: clip edges, markers */
int64_t rc_snap_resolve(const char *candidates_json, int64_t t, int64_t threshold, bool *snapped_out);

/* time */
int64_t rc_time_snap_to_frame(int64_t t, uint32_t fps_num, uint32_t fps_den);
char   *rc_timecode_format(int64_t t, uint32_t fps_num, uint32_t fps_den, bool frames);
bool    rc_timecode_parse(const char *s, uint32_t fps_num, uint32_t fps_den, int64_t *out);

/* export */
char *rc_export_presets(void);                                          /* [{id, name, container, codec, size, ...}], one per encoding */
char *rc_export_sizes(const RcProject *p, const char *preset_id, char **err_out); /* [{id, name, width, height}], the default first */
char *rc_export_settings(const RcProject *p, const char *preset_id, const char *overrides_json, char **err_out);

/* agent — same signatures as Rasterize's rz_agent_* (copy them) */
```

The Swift wrapper `ReelCore.swift` is the only file that calls `rc_*`.
`ReelProject` owns a handle and lazily decodes `rc_project_to_json` into a
`Codable` `ProjectSnapshot` — the typed, read-only view every Swift view
draws from. Writes are typed Swift methods (`func split(clips:at:)`) that
build the op JSON; there is no untyped call site outside `ReelCore.swift`.
The op schema table lives in the module doc of `edit.rs` (the `adjust.rs`
"module doc is the schema" pattern) and `ReelCore.swift` mirrors it.

### 7.2 Composition plan

Rebuilt by Swift only when the plan JSON differs from the current one
(a string compare; the plan is cheap to compute, so Swift asks for it after
every edit and compares).

```json
{
  "timescale": 600000, "duration": 36000000, "fps": [30, 1],
  "render_size": [1920, 1080],
  "video_tracks": [
    { "id": 1, "segments": [
        { "clip": 17, "media": 1, "source_in": 3000000, "source_duration": 12000000,
          "start": 0, "duration": 12000000 } ] },
    { "id": 2, "segments": [ … ] }
  ],
  "audio_tracks": [
    { "id": 1001, "segments": [
        { "clip": 17, "media": 1, "source_in": 3000000, "source_duration": 12000000,
          "start": 0, "duration": 12000000, "pitch": "spectral" } ],
      "ramps": [ { "start": 0, "duration": 600000, "from": 0.0, "to": 1.0 },
                 { "start": 600000, "duration": 10800000, "from": 1.0, "to": 1.0 },
                 { "start": 11400000, "duration": 600000, "from": 1.0, "to": 0.0 } ] }
  ],
  "instructions": [
    { "start": 0, "duration": 12000000, "required_track_ids": [1, 2] },
    { "start": 12000000, "duration": 3000000, "required_track_ids": [] }
  ]
}
```

- **A/B assignment.** Per timeline track, clips in start order; each goes
  to the first composition track (of that timeline track's set) whose last
  segment ends at or before the clip's start; a new one is added when
  none does. With the overlap rule (§6) that is at most two per timeline
  track — except for a nest clip, which stands for a whole stack and needs
  as many as the nest's own tracks do. Composition track ids are stable
  small integers (video 1…, audio **1001…**) and Swift creates tracks with
  `preferredTrackID:` equal to them, so the recipe can name a track by the
  same id. The two ranges are far apart because `MAX_TRACKS` is 64 counted
  across the timeline *and* every nest, so up to 128 video ids can be
  handed out; `CompositionBuilder.makeTrack` throws on a collision rather
  than renumbering. Segments on one composition track never overlap; gaps
  are left empty (AVFoundation treats them as no frame). The whole
  assignment runs over the FLATTENED timeline: a clip inside a nest gets a
  segment at `nest clip start + its own start`, clipped to the nest clip's
  extent, exactly as a timeline clip does.
- **Speed / freeze.** `duration != source_duration` means Swift inserts
  the source range then `scaleTimeRange` to `duration`. A `still` clip is
  a segment whose `source_duration` is exactly one source frame — the
  freeze-frame idiom; no image extraction needed.
- **Audio envelopes** are per composition audio track, piecewise-linear,
  covering the track's whole extent, with fades, volume, volume actions
  (sampled at 1/30 s across their span) and ducking (every other clip's
  envelope multiplied by `level` over the ducking clip's extent with
  linear attack/release ramps) already folded in, **multiplied by the same
  quantities for every nest clip the segment is inside** — turning a nest
  down turns everything in it down, and muting one silences it. Muted
  clips and muted tracks produce a 0 envelope; `mono` is a per-segment flag Swift applies
  with `AVMutableAudioMixInputParameters` where possible (else ignored in
  M2, noted).
- **Instructions** tile `[0, duration]` with no gaps or overlaps (an
  AVFoundation requirement); a boundary wherever the set of visible
  layers changes — which includes every **inner** clip edge of a nest,
  since the invariant the tiling rests on is that membership at a span's
  first tick holds for the whole span. Hidden tracks contribute nothing,
  inside a nest as much as outside. `image`, `text` and `shape` clips
  need no composition track and do not appear in `required_track_ids`.
- The decoder budget: warn (in the plan, `"warnings": [...]`) when more
  than 8 video composition tracks are required by one instruction.

### 7.3 Frame recipe

Asked once per frame by the compositor, and by the overlay for hit-testing.

```json
{
  "t": 6120000, "canvas": { "width": 1920, "height": 1080, "background": [0,0,0,1] },
  "layers": [
    { "clip": 17,
      "source": { "kind": "track", "track_id": 1 },
      "source_size": [1920, 1080],
      "crop": { "l": 0, "t": 0, "r": 0, "b": 0 },
      "x": 0, "y": 0, "scale": 1.0, "rotation": 0, "opacity": 1.0,
      "corner_radius": 0, "shadow": null,
      "color": { "brightness": 0, "contrast": 0, "saturation": 0, "hue": 0 },
      "chroma": null,
      "filters": [], "reflection": null, "spotlight": null, "clip_rect": null,
      "transition": null },
    { "clip": 23,
      "source": { "kind": "text", "hash": "9f3c…", "text": { …resolved text props… } },
      "source_size": null,
      "x": -560, "y": -380, "scale": 1.0, "rotation": 0, "opacity": 0.72, … },
    { "clip": 31, "source": { "kind": "track", "track_id": 2 }, …,
      "transition": { "kind": "push_left", "progress": 0.4, "role": "in", "partner": 17 } }
  ]
}
```

- Layers are back-to-front. Every property is already evaluated through
  actions. `source.kind` ∈ `track` (a composition video track id),
  `image` (`media` id — Swift decodes with ImageIO and caches the
  texture), `text` / `shape` (the resolved description plus a stable
  content hash Swift caches textures by), `missing` (draw a slate).
- `source_size` is the media pixel size, or `null` for text (the renderer
  knows) and the box size for shapes.
- `filters`, `reflection` and `spotlight` (M3) are the §5.2 property groups
  already evaluated: an ordered list of `{ "kind", "amount" }` at most
  `MAX_FILTERS` long, and the two objects or `null`. They are always
  present, so a renderer never has to ask whether the key exists.
- `clip_rect` (M3) is `null`, or `{ "x", "y", "w", "h", "rotation" }` — the
  rotated rectangle in CANVAS pixels the layer is clipped to, with `x`/`y`
  the rectangle's CENTRE measured from the canvas's top-left corner and
  `rotation` in degrees clockwise. That frame is not the canvas-centre one
  a layer's own `x`/`y` use; it is the space the fragment stage's position
  already arrives in, which is the whole reason for it. Only a nested layer
  sets it — clipped to its nest's canvas rect — and everything else emits
  `null`.
- **A nest contributes one layer per drawing clip inside it** (§5.3), never
  a layer of its own, so a layer's `clip` names the clip that DRAWS — which
  for a nested layer is not a clip on the timeline, and may appear twice in
  one recipe when two clips show the same nest. A nested layer inherits its
  nest clip's `transition` when it has none of its own, so a dissolve into a
  nest dissolves everything the nest draws; the inherited `partner` then
  names a clip that was itself flattened away, which the compositor treats
  as no partner. Two things deliberately do not survive the flattening: a
  nest clip's `opacity` multiplies each inner layer separately rather than
  the composite (inner layers that overlap each other show through), and
  only the innermost `clip_rect` is carried, because a layer gets one
  rectangle and the intersection of two rotated rectangles is not one.
- During a transition both layers are present, adjacent, each carrying the
  same `kind` and `progress` with `role` `out` / `in`. The compositor
  draws them as one pair.
- The recipe is a few KB; parsing it per frame costs tens of microseconds.
  A binary form is a later optimization, not a design change.

### 7.4 Swift file map

| File | Owns |
|---|---|
| `ReelCore.swift` | the **only** `rc_*` caller; `ReelProject` (handle + lazy `ProjectSnapshot`), typed op builders, `RecipeSource` |
| `ProjectDocument.swift` | NSDocument, `.reelcut` package read/write, the single mutation point (`applyEdit`, live-edit trio), undo as a handle stack, dirty counting |
| `Playback.swift` | `AVPlayer` + `AVPlayerItem` over the plan; the rebuild-vs-refresh decision (§7.6); coalesced exact seeks; JKL rates; loop range; `preferredMaximumResolution` = canvas size |
| `CompositionBuilder.swift` | plan JSON → `AVMutableComposition` + `AVMutableAudioMix` + `AVMutableVideoComposition` (+ `CompositionInstruction`) |
| `Compositor.swift` | the `AVVideoCompositing` class and its Metal pipeline (§7.5) |
| `LayerRenderers.swift` | text (Core Text) and shape (Core Graphics) descriptions → premultiplied BGRA `MTLTexture`s, LRU-cached by hash; reports measured text sizes to the overlay |
| `MediaImporter.swift` | `AVURLAsset` probing (the **one** place `async`/`await` is allowed — AVFoundation's loading API is async-only going forward), thumbnails via `AVAssetImageGenerator`, peaks via `AVAssetReader` + vDSP, cache files in the package |
| `Exporter.swift` | picks the pipeline for the core's settings — `ExportWriter` (`AVAssetReader`/`AVAssetWriter`: chapters, explicit bitrates) or the ImageIO frame sequence for GIF/APNG — reports progress, and renders one frame offline for `render_frame` |
| `TimelineView.swift` | custom `NSView` in an `NSScrollView`; drawing from the snapshot; gesture sessions (`ClipDragSession`, `TrimSession`, `RangeSession`, `MarkerDragSession`) as structs; `on*` closures to the VC |
| `PreviewCanvasView.swift` | `AVPlayerLayer` under a transparent overlay `NSView`; `CanvasSession` structs for move/scale/rotate/crop; handle drawing |
| `InspectorViewController.swift` + `VideoPane` / `AudioPane` / `TextPane` / `ShapePane` / `MediaPane` / `DocumentPane` | one file per tab, descriptor-driven controls from `OptionControls.swift` |
| `EditorViewController.swift` + `EditorViewController+<Feature>.swift` | wiring only in the base file; features in extensions (Rasterize's frozen-file rule) |
| `AppDelegate.swift` · `EditorWindowController.swift` · `WelcomeWindowController.swift` · `main.swift` | menus (nil-target selectors), window, welcome |
| `AgentServer.swift` · `AgentCatalog.swift` | MCP mirrors of every op, plus `open_project`, `import_media`, `render_frame` |
| `Theme.swift` · `Controls.swift` · `OptionControls.swift` · `Sheets.swift` | copied from Rasterize |

### 7.5 Compositor

`final class Compositor: NSObject, AVVideoCompositing`.

- `sourcePixelBufferAttributes` and `requiredPixelBufferAttributesForRenderContext`:
  `kCVPixelFormatType_32BGRA`, Metal-compatible. HDR sources are
  tone-mapped to SDR by AVFoundation as a consequence.
- `startRequest` runs on a serial queue: `renderContext.newPixelBuffer()`
  → `MTLTexture` through a `CVMetalTextureCache`; sources by
  `request.sourceFrame(byTrackID:)`; the recipe from `RecipeSource`
  (§7.6) at `request.compositionTime`; encode; on completion
  `request.finish(withComposedVideoFrame:)`. `cancelAllPendingVideoCompositionRequests`
  flushes the queue. Errors call `finish(with:)`, never crash.
- **One pipeline, one pass per layer.** The vertex stage places a quad
  from a per-layer uniform block (canvas size, center, source size, scale,
  rotation, crop window as UV bounds); the fragment stage samples with
  the crop window, applies the corner-radius mask (a rounded-rect SDF in
  source pixels), brightness/contrast/saturation/hue, chroma key (M3),
  and opacity, and outputs premultiplied BGRA blended source-over.
  Text and shape textures are already premultiplied and take the same
  path. Missing media draws a slate.
- **Transitions** are one pass over the pair: dissolve = both with
  progress-weighted opacity; fade black/white = out fades to the color
  then in fades from it; push/slide = offset by progress; wipe = a UV
  threshold; zoom = scale ramp. Shadows (M3) render the layer's alpha to
  a small offscreen texture, blur with `MPSImageGaussianBlur`, draw first.
- Budget: a 1080p frame in under 8 ms. Textures for image/text/shape
  layers are LRU-cached (64 entries).

### 7.6 Playback update rules

After every edit, `ProjectDocument` posts a change notification with the
new `ReelProject` and `isLive`. `Playback` then:

1. Sets `RecipeSource.current = newProject` (an atomic reference the
   compositor reads on every request).
2. Computes the plan JSON; if it equals the current plan, the edit was
   **property-only**: no rebuild — if paused, re-seek to the current time
   with zero tolerance to force one composed frame (the standard trick for
   redisplaying a paused `AVPlayer`).
3. Otherwise the edit was **structural**: rebuild the composition on a
   background queue, swap `AVPlayerItem` at the same time, keep the play
   state. Rebuilds are debounced at 80 ms during live gestures
   (`isLive`), and the final `endLiveEdit` always rebuilds if needed.
4. Instructions carry the plan's instruction ranges only; the
   compositor's `RecipeSource` is what makes property edits render
   without a rebuild.

Scrubbing: the timeline coalesces to one in-flight `seek(to:toleranceBefore:.zero,toleranceAfter:.zero)`
at a time, dropping intermediates.

### 7.7 Import

`MediaImporter.probe(url)` (async): loads `duration`, video/audio tracks,
`naturalSize` × `preferredTransform` (so rotated phone footage reports its
display size), `nominalFrameRate` (converted to the nearest rational
among the common rates, else `[round(fps × 1000), 1000]`), alpha
(`hasAlphaChannel` on the format description), and returns the `media[]`
descriptor for `add_media`. Thumbnails: 160 px tall, one per second up to
600, JPEG in `cache/thumbs`. Peaks: mono float, 100 buckets/s, in
`cache/peaks`. Both run in the background after import and the timeline
redraws as they land. Image files (PNG/JPEG/HEIC) are probed with ImageIO
and become `kind: image` media.

Formats AVFoundation opens on macOS 15: MOV, MP4, M4V, M4A, MP3, AAC, WAV,
AIFF, CAF; H.264, HEVC, ProRes, MJPEG; PNG/JPEG/HEIC/TIFF images. MKV,
WebM, AVI and VP9/AV1 are not opened (§11).

### 7.8 Export

Presets (`rc_export_presets`), in menu order, are ENCODINGS — a container
and a codec, with no size of their own: `h264` H.264 (MP4), `hevc` HEVC
(MP4), `prores_422` ProRes 422 (MOV), `audio_m4a` Audio only (M4A), `gif`
Animated GIF, `apng` Animated PNG. The size is a separate choice whose
default is the document's own size, so a 1440p or a vertical project does
not come out at 1920 × 1080 because a row said so; the two image formats
are the exception and carry the cap argued below. **The first row of each
list is the default.** The export sheet opens on `h264`, and its Size
popup on the first row of `rc_export_sizes(project, preset)`, which lists
the sizes offered for that document and format: the document's size
(`document` — "Document size", not "source size": §4.3's source size is a
media item's, and this row renders at the canvas), or for an image format
its cap (`preset`) with the document's size second; then the standard
sizes fitted to the document's aspect, largest first — `2160p` (named 4K),
`1440p`, `1080p`, `720p`. The number is the SHORT edge, because "1080p
ultrawide" is 2560 × 1080 and "1080p vertical" is 1080 × 1920 — the short
edge is the number people mean — and the long edge is the document's,
scaled to match and rounded to the nearest even integer, since H.264 and
HEVC need even dimensions and a size the writer would quietly change is
not one the sheet may offer. A row may repeat an earlier row's numbers —
a 1920 × 1080 document's `1080p` is its own size — and is listed anyway,
because an id is the `export` tool's vocabulary and has to mean the same
thing on every document; the sheet hides a row whose numbers an earlier
row already has, keeping the name that says more. On an image format
every row's numbers are the canvas fitted inside that box, never upscaled
(below). The audio-only preset lists the same rows as `h264` and the sheet
disables the control. The agent's `export` takes the same ids in its
`size`, or an explicit `[width, height]` (the sheet's "Custom…").
`rc_export_settings` resolves a preset plus overrides (size, fps, range =
whole or in/out, `optimize_for_network`, and the two bitrates below) to
concrete settings, no size override meaning the preset's cap where it has
one and the canvas otherwise. Each preset AVFoundation can write still
carries an `AVAssetExportSession` preset name
(`AVAssetExportPresetHighestQuality`, `…HEVCHighestQuality`,
`…AppleProRes422LPCM`, `…AppleM4A`) — that mapping is what names the
codec and tier, and `avf_preset: null` is how a preset says AVFoundation
cannot write it at all. But **nothing runs a session any
more**: M2's `AVAssetWriter` path REPLACED it rather than joining it, for
the reason the whole design exists — two writers would make the chapter
track, the explicit bitrates and the output size conditional on which one
happened to run, and leave two answers to "what did the file end up as".
`ExportWriter` reads the composition through an `AVAssetReader` and writes
video, audio and a chapter track (an `AVAssetWriterInput` text track
associated `AVTrackAssociationTypeChapterList`), reporting `progress` on
the same timer the sheet already polled. GIF and APNG take the ImageIO
path instead, frame by frame over `Exporter.renderFrame`.

**Quality.** `video_bitrate` and `audio_bitrate` are overrides in bits per
second, strictly positive; a zero, a negative, a fraction or a non-number
is an error naming the value. No preset carries a default and neither key
appears in the resolved settings unless it was asked for: on the session
path the preset name IS the bitrate ladder, and on the writer path
VideoToolbox's size-derived rate beats any constant the table could hold.
Absent therefore means "the encoder decides", which is exactly what
`ExportSettings.videoBitrate == nil` says on the Swift side.

**GIF and APNG.** AVFoundation writes neither, so their rows resolve to
`avf_preset: null` — the signal to write the file frame by frame through
`CGImageDestination` instead of building a session — and to `audio: false`,
which is a fact about the containers rather than a choice about the
project. `file_type` is still the file's real UTI (`com.compuserve.gif`;
`public.png`, an APNG being a PNG carrying `acTL`/`fcTL` chunks), so the
save panel's content type and extension are right on either path. Both cap
what the project would otherwise supply, because their cost is frames ×
pixels and nothing else: GIF at 480 × 270 and 12.5 fps (a GIF frame delay
is a whole number of hundredths of a second, and 8 cs is the longest that
still reads as motion), APNG at 960 × 540 and 25 fps (true colour and
lossless, so it earns the extra pixels, and an `fcTL` delay is an exact
rational needing no such rounding). Both caps are defaults a size or fps
override replaces. On these two formats a size — the cap, a row of the
Size popup, a custom size — is a box the picture is FITTED inside, aspect
kept and never upscaled, where the movie writer letterboxes to exactly the
frame asked for (`AVVideoScalingModeResizeAspect`): padding a GIF costs
bytes in every frame for pixels that carry nothing, and a bigger frame
carries no more detail. The core does the fitting (`export_size.rs`,
applied by `rc_export_settings` and `rc_export_sizes` alike), so the Size
popup, the sheet's readout and the `export` tool all report the numbers
the file will have — a vertical 1080 × 1920 timeline's "GIF default" is
152 × 270 — and `ExporterImageSequence` draws each frame at exactly that
size rather than fitting a second time.

### 7.9 Agent

`agent.rs` is copied from Rasterize (generic streamable-HTTP MCP, tools
only). Catalog: one tool per §6 op with the same name and arguments, plus
`open_project {path}`, `new_project {path?}`, `import_media {path}` →
media id, `save_project`, `get_project` → the JSON, `set_playhead`,
`set_range`, `set_selection` and `undo` / `redo` (the view state and the
history are app state, not ops, but without a setter for each the "one
edit is one undo step" and "the in/out range scopes the export" properties
cannot be checked by driving the built app),
`render_frame {t, max_width?}` → PNG (the verification hook: the
compositor renders offline through an `AVAssetImageGenerator` over the
same composition + video composition), and
`export {preset, path, size?, range?, video_bitrate?, audio_bitrate?}` —
the export sheet's five controls in the sheet's own vocabulary (all but
the frame rate: the tool exports at the document's, or on GIF and APNG at
the format's cap), so an agent export and a menu export can ask for the
same file. Handlers
use `performGroupedEdit` so off-event edits get their own undo group
(Rasterize's `AgentServer.performGroupedEdit`). Default port 4817; env
`RC_AGENT_PORT`; launch flag `-AgentServerEnabled YES`.

### 7.10 Rust module map

Crate `reelcut_core`, `crate-type = ["staticlib", "rlib"]`, deps `serde`,
`serde_json`, `tiny_http` (agent). Soft cap 600 lines per module; a new
concern is a new module with its own `impl Project` block.

| Module | Owns |
|---|---|
| `lib.rs` | declarations and re-exports only |
| `model.rs` | the §5.2 types, serde derives, id allocation, invariants (`validate`) |
| `time.rs` | `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`) |
| `edit.rs` | the op enum + serde, `apply(&self, op) -> Result<Option<Project>, String>`; **its module doc is the op schema table** |
| `edit_clip.rs` / `edit_props.rs` / `edit_track.rs` / `edit_time.rs` | the §6 ops in `impl Project` blocks: clip placement; the four property patches and their range checks; tracks, markers, canvas, media; ripple, insert time, range delete, freeze |
| `edit_action.rs` / `edit_nest.rs` / `edit_paste.rs` | the ops with a concern of their own: actions (the no-overlap rule); `nest` / `unnest`; `paste` (making another document's clips fit) |
| `actions.rs` | evaluation and interpolation, `clip_state(clip, t)` |
| `transition.rs` | overlap detection, the overlap rule, progress at *t* |
| `evaluate.rs` | `frame_recipe(t)`, `composition_plan()` (A/B assignment, instructions) |
| `nest.rs` | flattening a nest: the walk that turns a nest clip into the clips it stands for, and the transform they inherit |
| `audio.rs` | envelopes: fades, volume actions, ducking, mute |
| `snap.rs` | candidates and `resolve` |
| `format.rs` | `RC_FORMAT_VERSION`, `RC_CAPS`, read-any-version / write-current |
| `export.rs` | presets (one per encoding) and settings resolution |
| `export_size.rs` | `export_sizes(preset)`: the Size popup's rows — the document's size, an image format's cap, the standard sizes fitted to the document's aspect by the short-edge rule — and `fit_within`, the rule for what a size means on an image format, which `export_settings` applies too |
| `agent.rs` | MCP server (copied) |
| `ffi.rs` / `ffi_edit.rs` / `ffi_query.rs` / `ffi_agent.rs` / `ffi_util.rs` | thin shims; `ffi_util` holds `catch_unwind` + `err_out` + CString helpers (copy Rasterize's) |

Tests: black-box in `core/tests/` through the FFI, oracle-checked, no
golden files. Required from M1: JSON round-trip for every field; timecode
table (including 29.97 and 23.976 boundaries); split-then-rejoin (a
`join` helper in tests only) is the identity; `ripple_delete` preserves
every relative gap on unlocked tracks and touches nothing on locked ones;
`move_clip` overlap rule accepts/refuses the documented cases; a recipe is
continuous across an action boundary (evaluate at `end − 1` and `end`);
a plan's instructions tile the duration; `apply` with an unknown op or a
bad id is `Err`, never a panic; the NULL-safety sweep over every export.

## 8. Repo layout, build, conventions

```
reelcut/
  CLAUDE.md           # points here; commands; the rules below
  Makefile            # app / test / lint / typecheck / project / run — Rasterize's, renamed
  project.yml         # xcodegen; macOS 15, arm64; document types below
  core/
    Cargo.toml        # reelcut-core; lib name reelcut_core; serde, serde_json, tiny_http; lto
    include/reelcut_core.h
    src/  tests/
  app/
    Bridging/Reelcut-Bridging-Header.h
    Sources/          # AppKit, programmatic, no storyboards
    Resources/Fonts   # Source Sans 3, IBM Plex Mono, Darker Grotesque (+ OFL files)
    Assets.xcassets   # AppIcon
  designs/            # this document
```

`project.yml` document types: `com.kgalligan.reelcut-project` (Owner,
`.reelcut`, conforms to `com.apple.package`), then as Alternate editors:
`com.apple.quicktime-movie`, `public.mpeg-4`, `com.apple.m4v-video`,
`public.movie`, `com.apple.m4a-audio`, `public.mp3`, `com.microsoft.waveform-audio`,
`public.aiff-audio`, `public.png`, `public.jpeg`, `public.heic`.
`ProjectDocument.read(from:ofType:)` on a non-package type imports the
file into a fresh project and marks the document untitled.

Commands (identical to Rasterize's):

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release
make lint       # cargo clippy --all-targets -- -D warnings
make typecheck  # swiftc -typecheck of app/Sources/*.swift with the bridging header — the ONLY Swift check
make project    # xcodegen generate
make run
```

Files to copy from `~/devel/rasterize` at scaffold time, then rename:
`Makefile`, `project.yml`, `.gitignore`, `core/src/agent.rs`,
`core/src/ffi_util.rs`, `app/Sources/Theme.swift`, `Controls.swift`,
`OptionControls.swift`, `Sheets.swift`, `FileDropView.swift`,
`WelcomeWindowController.swift`, `app/Resources/Fonts/*`. Read before
writing the corresponding Reelcut file: `ImageDocument.swift` (undo and
dirty tracking), `RasterCore.swift` (wrapper shape), `AgentServer.swift`
+ `AgentCatalog.swift` (dispatch and parity check), `LivePhotoLayer.swift`
(AVFoundation frame extraction), `ToolOptionsBar.swift` +
`EditorViewController+ToolOptions.swift` (descriptor-driven controls),
and both `CLAUDE.md` files under `core/` and `app/`.

Rules carried over verbatim: pure ops returning `Option` (identity is
`None`); the three-file lockstep (`ffi_*.rs` → header → `ReelCore.swift`)
— with JSON ops the header changes rarely, but the op table in `edit.rs`
and the builders in `ReelCore.swift` still move together; every export
`catch_unwind` + NULL-tolerant + `err_out`; no panics on any input; the
frozen-file / extension-file rule (base VC, canvas, timeline, agent server
and sheets take wiring only); one document mutation point; no `!`, `as!`,
`try!`; `[weak self]`; main-thread AppKit; `async`/`await` only inside
`MediaImporter`; `DispatchQueue` only at the documented seams (compositor
render queue, composition rebuild, import); MCP parity for every op;
`DS` tokens for all chrome; 4-space indent, ~100 columns; `cargo fmt` and
a clean `make lint` before finishing Rust work.

## 9. Keyboard map and menus

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
| ⌥⌘D | Detach audio |
| ⌥⌘K | Add action at playhead |
| M | Add marker |
| I / O / ⌥X | Set in / set out / clear range |
| N | Toggle snapping |
| T | Add text clip at playhead |
| C | Crop mode on the selected clip |
| ⇧Z | Fit timeline |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit (canvas, or timeline when focused) |
| ⇧⌘N | New track |
| ⇧⌘I | Add media… |
| ⌘G / ⇧⌘G | Nest / un-nest (M3) |
| ⌘E | Export… |
| ⌥⌘I | Toggle inspector |
| ⌥-drag clip | Duplicate |
| ⌥-drag clip edge | Rate stretch |
| ⌘-drag | Suppress snapping |

Menus: File (New Project, Open…, Open Recent, Close, Save, Save As…,
Add Media…, Consolidate Media… (M3), Export…), Edit (Undo, Redo, Cut,
Copy, Paste, Duplicate, Delete, Ripple Delete, Select All, Select After
Playhead), Clip (Split, Trim Start, Trim End, Freeze Frame, Detach Audio,
Add Action, Speed…, Transition ▸, Nest, Un-nest), Track (New Track,
Remove Track, Remove Empty Tracks, Hide/Mute/Lock), Mark (Add Marker,
Set In, Set Out, Clear Range, Next/Previous Marker), View (Zoom, Fit,
Snapping, Safe Areas, Inspector, Timeline Track Height), Window, Help.
All menu items are nil-target selectors validated in
`validateUserInterfaceItem`.

## 10. Milestones and the M1 build order

**M1 — Cut.** The point at which a screencast editor stops getting opened: open a
file into a project at the source's size and rate; import more; tracks;
move / trim / split / delete / ripple; play, scrub, JKL; transform, crop
and opacity on the canvas and in the inspector; markers; save and open
`.reelcut`; undo; export H.264 and HEVC.

**M2 — Compose.** Text, shapes, transitions, audio volume / fade / duck /
detach, freeze frame, speed, in/out range, chapters on export, the MCP
agent with parity for everything above.

**M3 — Polish.** Actions, corner radius / shadow / reflection, chroma key,
color controls, filters, nests, spotlight, GIF / APNG export, noise
removal, SRT captions (import and burn-in), Consolidate Media, ffmpeg-
assisted import.

### M1 in order, each step verified before the next

1. **Scaffold.** Copy and rename the build files (§8); `core` with
   `rc_project_new/free/to_json/from_json` + `rc_string_free`; the header;
   `main.swift`, `AppDelegate`, `ProjectDocument` (package type),
   `EditorWindowController`, `EditorViewController` with the three panes
   as empty `NSSplitView` children and `DS` chrome; welcome window.
   *Verify:* `make app` launches, `make test` runs a round-trip test,
   `make typecheck` is clean.
2. **Model, time, format** in Rust (`model.rs`, `time.rs`, `format.rs`,
   `edit.rs` skeleton with `add_media`, `add_track`, `add_clip`,
   `set_canvas`). *Verify:* the §7.10 round-trip and timecode tests.
3. **Import.** `MediaImporter.probe` → `add_media` → `add_clip`; opening a
   movie creates the untitled project; the Media tab lists it.
   *Verify:* project JSON in the debugger shows the right descriptor and
   one clip; a rotated iPhone clip reports its display size.
4. **Plan + playback, passthrough.** `composition_plan` for one track
   with no overlaps; `CompositionBuilder`; `Playback` with
   `AVPlayerLayer`; transport buttons, Space, JKL, timecode display.
   Use `passthroughTrackID` instructions for this step only.
   *Verify:* the clip plays with audio; seeking is frame-exact.
5. **Recipe + compositor.** `frame_recipe` (single layer),
   `Compositor` with the one-pipeline pass, instructions switched to the
   custom compositor, `RecipeSource`. *Verify:* changing `x`/`scale`
   through a debug op re-renders the paused frame without a rebuild;
   playback stays at 60 fps on a 1080p source (measure with the
   compositor's own timing log).
6. **Timeline view.** Ruler, tracks, clips from the snapshot, playhead
   drag, click-to-select, zoom, Fit, auto-scroll. *Verify:* visually,
   and the playhead time matches the timecode display.
7. **Edit ops + gestures + undo.** `move_clip`, `trim_*`, `split`,
   `delete`, `ripple_delete`, `insert_time`, `duplicate`; the drag/trim
   sessions; keyboard map; undo/redo; dirty flag. *Verify:* the §7.10
   op tests; in the app, every gesture is one undo step and undo restores
   the frame.
8. **Canvas overlay + Video tab.** Handles for move/scale/rotate, crop
   mode, snapping; `VideoPane` bound to `set_video` with the live-edit
   trio. *Verify:* dragging on the canvas updates the inspector live and
   commits one undo step.
9. **Markers + Document tab.** Add/move/rename markers, canvas size and
   fps ops with `rescale_clips`. *Verify:* op tests and the ruler.
10. **Export.** Presets (one per encoding) and sizes, the export sheet,
    `Exporter` over `ExportWriter`, progress, cancel. *Verify:*
    the exported file plays in QuickTime Player and matches `render_frame`
    at three times, and a project whose canvas is not 1920 × 1080 exports
    at its own size with the sheet's defaults.
11. **Multi-track + thumbnails + peaks.** A/B assignment and instruction
    ranges for several tracks, layer ordering, hidden/muted/locked
    tracks, filmstrips and waveforms from the cache. *Verify:* the tiling
    test; a three-track project composites in the right order.
12. **Files.** Save/open round-trip through the package, autosave, Recent,
    missing-media slate and Relink…, README. *Verify:* quit and reopen
    reproduces the timeline and the frame.

## 11. Decisions made — do not re-litigate

- **AVFoundation, not ffmpeg.** Risk: MKV, WebM/VP9 and AV1-in-MKV do not
  open. Mitigation (M3, landed): an opt-in import step that shells out to a
  user-installed ffmpeg (present at `/opt/homebrew/bin/ffmpeg` on the
  development machine) to rewrap or transcode. The conversion is written to
  `~/Library/Application Support/Reelcut/Rewrapped/`, **not into the
  package**, for two reasons the `FFmpegRewrap.rewrapDirectory` comment
  spells out: opening an MKV from the Finder makes an UNTITLED document, so
  the import that needs a conversion is exactly the one with no package to
  put it in; and `fileWrapper(ofType:)` is a two-child whitelist whose one
  surviving location, `cache/`, is documented-regenerable (§5.6) — the last
  place for the only decodable copy of someone's footage. The name carries
  a digest of path, size and modification date, so a conversion is reused
  and invalidates itself. `RCFFmpegImport` chooses the policy and
  `RCFFmpegPath` the binary; with neither ffmpeg nor a cached conversion
  the import fails exactly as it did before the feature existed.
- **Custom compositor from day one** (M1 step 5). `AVVideoCompositing`
  has sharp edges — pixel-buffer pools, timing, `renderContextChanged`.
  Building the single-layer version first de-risks every later effect.
- **`AVPlayerLayer` under an overlay view**, not a self-driven `MTKView`,
  for the preview: A/V sync and scrubbing come from the player; the
  overlay maps through `videoRect`.
- **One JSON op entry point** (`rc_project_apply`) instead of one C
  function per op. Trade-off accepted: argument checking moves to
  Rust (`Err`) and to the typed Swift builders; in return the header is
  stable and the MCP catalog is the same table.
- **The plan-string compare** decides rebuild vs. refresh. Simple, and
  correct by construction because the plan contains exactly the
  structural facts.
- **Overlap rule**: at most one neighbour per side, each overlap ≤ half
  the shorter clip; larger overlaps refuse. Clips never push.
- **Ripple is timeline-wide** across unlocked tracks (a screencast editor's
  behaviour); straddling clips on other tracks stay put.
- **Freeze frame keeps sync** by inserting time across all unlocked
  tracks, and is a one-source-frame segment scaled in the composition —
  no image extraction.
- **Ducking is by clip extent**, not voice activity (a screencast editor's rule),
  so no audio analysis is needed for it.
- **Speed and pitch** come from `scaleTimeRange` and the time-pitch
  algorithm. Reverse is not native; M3 pre-renders reversed segments.
- **Text and shapes are described, not rasterized, in the model.** The
  recipe carries the description; the platform renders it (Core Text /
  CG). Measured text sizes live in a Swift cache, never in the model.
- **Time is 600 000 ticks/s.** Mixed source rates resolve at render, never
  in the model.
- **No left panel.** Media is an inspector tab. Revisit if libraries grow
  past a few dozen files.
- **`async`/`await` is allowed only in `MediaImporter`.** Everything else
  keeps Rasterize's synchronous AppKit discipline.
- **Media is referenced, not copied**, by path + bookmark (not
  security-scoped; the app is not sandboxed). Consolidate is M3.
