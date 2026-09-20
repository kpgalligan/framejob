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

a screencast editor's editor without a screencast editor's recorder — and, since road map 3,
a recorder of the SCREEN alone, whose output is ordinary media. Open one or
more video files from disk, arrange them on layered tracks over a fixed canvas, trim,
split, annotate, animate, and export. Mac only, Apple Silicon, macOS 15+.

The bar is a screencast editor's balance: enough to make a real cut with text,
shapes, transitions and simple animation, without Final Cut's magnetic
timeline, roles, multicam, scopes, or a plugin ecosystem.

Deliberate non-goals: camera recording, multicam, color grading beyond
per-clip controls, audio beyond volume/fade/duck, a plugin system, any
platform but macOS. **Screen recording was on this list until road map 3
reversed it** (§11): the app records a display or a window through
ScreenCaptureKit into a file it then imports exactly as File ▸ Open would —
paused and resumed from the menu bar, each stretch its own file and its own
clip; camera capture and callouts reconstructed after the fact stay out.

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

The chrome below is the one the design handoff in
`designs/design_handoff_reelcut/` specifies; it replaced the first cut, whose
toolbar was a grab bag, whose Export was a system pill, and whose clips had no
visible boundary. That handoff's README is the normative source for the
metrics; this section is the summary.

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                    Demo — 1080 × 1920 · 25 fps · edited          (OS title bar) │
├────────────────────────────────────────────────────────────────────────────────┤
│ ⏮ ◀◀ ▶ ▶▶ ⏭ ↻ │ 00:00:20:12 / 00:01:00:00          [Fit ▾] [Safe] │ [⤴ Export…] │
├───────────────────────────────────────────────────────┬────────────────────────┤
│                                                       │  Clip  Media  Document │
│      ┌─────────────────────────────────────────┐      │────────────────────────│
│      │ Intro title                             │      │ ▌clipA.mov             │
│      │                                         │      │  video · 00:00:21:00 … │
│      │            (screen recording)           │      │ ▾ TRANSFORM       100% │
│      │                                     ──▶ │      │   Scale    ──o──  100 %│
│      │                           ┌────────┐    │      │   Position x 480 y 270 │
│      │                           │ webcam ○┼   │      │ ▸ CROP        none [⟲] │
│      │                           └────────┘    │      │ ▸ CORNER RADIUS 0 px   │
│      └─────────────────────────────────────────┘      │ ▸ SHADOW           off │
│        1080 × 1920 · 25 fps                           │ ▸ SPEED         1.00×  │
│                                                       │ ▸ TIMING  00:00:21:00  │
├───────────────────────────────────────────────────────┴────────────────────────┤
│ ▌clipA.mov     │ ✂ ⇥ ⇤ ⌫ ◆ ⧉ Aa ▭ │ Snap ●  ▁▃▅▂  ⊖ ──o── ⊕ ⇔ │ [S][M][L]     │
│  V1 · video    │                                                               │
├────────────────────────────────────────────────────────────────────────────────┤
│          ┆0:00      0:10   ▼  0:20      0:30      0:40      0:50      1:00     │
│ T1       ┆ [Aa Intro title      ]                                              │
│ V1       ┆ [▦ Screen recording.mov ███████████████████][/][▦ B-roll ██████████] │
│ A1       ┆ [∿ Music.m4a ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~]  │
└────────────────────────────────────────────────────────────────────────────────┘
```

| Region | Default | Range | Holds |
|---|---|---|---|
| Title bar | OS | — | the document name, and its size · rate · edited state as the subtitle |
| Toolbar | 44 pt | fixed | transport, timecode, canvas zoom, safe guides, Export |
| Preview canvas | flexible | — | the composition at canvas size, letterboxed in the void |
| Inspector | 304 pt | 280–440, collapsible (⌥⌘I) | three tabs + collapsible sections |
| Timeline bar | 36 pt | fixed | the selection block, the clip actions, snap, the output level meter, zoom, S/M/L |
| Timeline | 300 pt | 140 pt – 60 % of window | ruler, track headers + lanes |

The toolbar carries only what applies to the whole document at all times —
*where you are in it*, *how you are looking at it*, and *getting it out*.
Everything that acts on a clip is in the timeline bar, beside blade and
ripple-delete. Document identity is the title bar's, because the OS already
gives it a home.

Inspector and timeline are `NSSplitView` panes; sizes persist in
`UserDefaults`. There is no left panel: the media library is an inspector
tab, as in a screencast editor, so the canvas gets the width. Below about 1080 pt wide,
narrow the inspector before anything else. The window has a welcome sibling
(`WelcomeWindowController`, as in Rasterize) offering Open Video…, New
Project, New Recording… (road map 3) and Recent, under the stacked wordmark.

## 4. The regions in detail

### 4.1 Toolbar

44 pt, `BarView(border: .bottom)`, 12 pt padding, 12 pt between clusters, with
a 1 pt `DS.border` rule between them.

- **Transport**: six `GhostButton`s at 34 × 26 pt on the 4 pt button radius,
  19 pt symbols, 2 pt gaps — go to start, previous edit point, play/pause,
  next edit point, go to end, loop (loops the in/out range when set, else all).
- **Timecode** in the mono face: a 24 pt bordered field on the button radius
  holding the current time, then the duration in `DS.mono(11)`
  (`00:00:20:12 / 00:01:00:00`), in the document's frame rate. Click to type a
  time; accepts `1:23`, `83.5`, `1:23:04`. A Document setting switches frames
  to milliseconds. Formatting and parsing are core functions
  (`rc_timecode_format` / `rc_timecode_parse`).
- **Canvas zoom** popup (Fit, 50, 100, 200 %) and a title-safe /
  action-safe guide toggle (90 % and 80 % rectangles).
- **Export…** (⌘E) is an `AccentButton`: 26 pt, the 4 pt radius, `DS.accent`
  fill, `DS.onAccent` at 12 pt semibold, a 15 pt `square.and.arrow.up` at a
  6 pt gap. Hover lightens the fill; that is the whole state model. It is
  deliberately **not** `StickerButton` — the sticker pill was retired in the
  Rasterize redesign and the chrome follows, square-ish and quiet.
  `StickerButton` stays for the sheets and the welcome screen.

Add Text, Add Shape, Add Marker and Duplicate are in the **timeline bar**
(§4.4), because each acts on a clip. Snapping is there too, because it is a
timeline concern.

### 4.2 Preview canvas

- The composition at document size, centered in the void
  (`DS.canvasVoid`) with a 24 pt margin; the canvas background is the
  document's background color. Zoom with ⌘= / ⌘- / ⌘0 (fit) or pinch;
  Space-drag pans when zoomed in.
- Shows the frame at the playhead. During playback the frames come from
  the player; while scrubbing or editing, from exact seeks.
- The size caption under the video is mono 10 pt in `DS.textFaint` with
  0.06em tracking, matching every other machine-produced number in the app.
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
- **Region mode** (Z, or the Video sections' "Zoom to Region…" and the
  Obscure section's "Place on Canvas"): a modal overlay over the canvas on
  which a rectangle is dragged free — no aspect lock, which is what makes
  `fill` reachable at all. While a ZOOM drag runs, the rectangle that will
  actually end up filling the canvas is stroked dashed in the same ink at a
  lower alpha — larger than the band under `fit`, smaller under `fill` — so
  what you will get is on screen. Release commits: a zoom action at the playhead
  (⇧ chooses fill over fit) or an appended `video.obscure` region,
  whichever armed the mode. Z toggles, Esc cancels, and moving the
  selection ends it; the mode refuses to arm at all when there is no
  single selected clip on the canvas at the playhead, since there would be
  nothing to draw a rectangle over. A band under 6 px on either axis beeps
  and leaves the mode armed — a stray click is a miss, not a decision. The
  rectangle is read in §5.3's source-pixel frame through all four of its
  corners, so a rotated layer gets the right box. Arming ANY modal canvas
  mode ends whatever other one was armed — the eyedropper and the region
  band are one overlay each and only one may be up, or a drag begun for one
  commits the other's edit.
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

Tab strip across the top: **Clip, Media, Document** — `PanelTabsView`, all
three always live. Clicking a clip anywhere shows the Clip tab, including a
click that re-picks the clip already selected. Multiple selected clips edit
their common properties together (one op with several clip ids).

It was six tabs — Video, Audio, Text, Shape, Media, Document — with a
disabled state per tab, a most-relevant-tab rule and a pin to defeat it. Four
of the six were about the same thing, the selected clip, and 304 pt gave each
about 50 pt of strip. They are now SECTIONS inside the Clip tab, and which
sections appear is a function of the selection's kind (`ClipPane.makeSections`)
— the piece of logic that replaces the whole tab-visibility apparatus. With
that, a pin protects nothing and is gone.

The Clip tab opens with a 44 pt selection header: an 8 × 26 pt tint chip in
the clip's kind colour, the name at 12 pt semibold, and a mono 10 pt line
giving the kind word, the duration in the DOCUMENT's timecode, and the
source's own facts. `ClipKindStyle` is the one mapping from a clip to that
chip, and the timeline bar and the timeline's own name strips read it too, so
the three views of one selection agree by construction.

Since format version 3 that name line is, for a SINGLE selected clip, an
editable field (`InspectorNameField`) showing the DISPLAYED name —
`ProjectSnapshot.name(of:)`: the clip's own name, else the fallback. Its
commit sends the trimmed text through `set_clip`, and an emptied field on a
clip with a name of its own sends `null`: this is the one place in the UI a
name is cleared back to the fallback, because the shared rename editor the
timeline uses for tracks, markers and clips drops an empty commit (a track
or marker name cannot be cleared). Emptying a field that already showed the
fallback sends nothing. A multi-selection keeps the drawn "N clips
selected". A label every selected clip shares draws as a 6 pt dot at the
line's right end — the strip's dot, so the two views agree — and the mono
line sits at y 27 under the 20 pt field.

Sections are disclosure groups with a reset-to-default in the header, a
right-aligned mono 10 pt summary of the group's current state (`100%`,
`neutral`, `+0.0 dB`, `off`) so a collapsed group still tells you something,
and per-section open/closed state in `UserDefaults`. Transform opens by
default and the rest are closed; a selection that gets no Transform — an
audio-only clip — opens its first section instead, so the panel is never a
wall of shut headers.

**Note on the section list.** The design handoff's table sketches five groups
(Transform, Video, Audio, Effects, Timing). What shipped keeps the panes'
EXISTING sections as the units and filters them by kind, because merging them
would have thrown away every per-section Reset button and every
evaluated-action note. The handoff's own implementation note asks for exactly
that — the rows move "largely as-is", and the work is the shell and the
kind-to-sections function.
Controls are Rasterize's `OptionControls` family: slider + field pairs
with quick-value chevrons, color wells, steppers.

The section groups below are named as they were when each was a tab; they
are now sections of the Clip tab, offered when the selection has that aspect.

**Video sections** — any clip with a video property group, which is every
clip that draws. A text or shape clip therefore gets Transform and the
whole effects group (Shadow, Filters, Reflection, Spotlight, Obscure) too:
those measure the layer against its own source pixels, and a title has
those as much as a movie does. What it does NOT get is the sections tied to
a source that has pixels of its own — Crop, Corner radius, Colour and
Chroma key — or to a media source, which is Speed.

- *Transform*: Scale % (1–1000), Position X / Y in canvas pixels (origin
  at canvas center, X right, Y down), Rotation °, Opacity %, and — format
  version 6 — **Blend**, a popup over the eight modes of §5.2's
  `video.blend`, beside Opacity because the two are the same question
  about how this layer meets what is under it. Buttons: Fit to canvas,
  Fill canvas. The one trap the feature has is answered in place rather
  than in a manual: every mode but `normal` is a function of TWO colours,
  so a layer with nothing behind it over the default black canvas either
  reads black (`multiply`, `darken`, `overlay` all collapse against 0) or
  changes nothing at all (`screen`, `add`, `lighten`, `difference` are the
  identity against 0). The section's note is COMPUTED — it appears only
  when there really is no visible layer behind the clip and the canvas
  background really is black, and it names which of the two failures is on
  screen — and the popup's tooltip carries the whole of it and the answer,
  which is Clip ▸ Add Background. `blend` is an ORDINARY animatable key,
  deliberately not one the list rule's structural exception pulls out: a
  discrete value inside an action holds and switches at the end, which is
  what §5.4 says a discrete value does.
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
  that action's end state and the section header says so — with one
  exception, ADDING or REMOVING an entry of a list-valued property
  (`video.filters`, `video.obscure`), which always writes the base props.
  §5.4's list rule interpolates per index only while the two lengths
  match, so a longer or shorter list in an end patch would be invisible
  for the whole span and then be overwritten by the next write of that
  list; dialling a value INSIDE an entry still animates.
- *Transition* appears when the clip overlaps its predecessor: kind,
  curve, whether the two clips' sound crosses over, and duration. The
  Curve popup and the Crossfade Audio checkbox both read the FILE's
  defaults (`linear`, off) rather than what the core would mint — the
  section says what is there — and when the clip has no stored transition
  at all each of the two sends BOTH keys, so the transition that gets
  minted is exactly what the section was showing and only the touched
  value moves.
- M3: *Chroma key* (key color with a canvas eyedropper, tolerance,
  softness, spill suppression), *Reflection*, *Filters* (blur, sharpen,
  pixelate, sepia, noir, vignette, invert — Core Image behind them).
- M3: *Spotlight* — the stand-in for a screencast editor's freehand callout — lives
  here rather than in the Shape pane below, because only the layer that
  owns the pixels can draw its 1.2–2× zoom.
- Format version 4: *Obscure* — up to four regions that hide what is under
  them, six rows each (kind with a Remove button, then shape, amount,
  feather, and the centre and the size as PAIRED fields rather than the
  spotlight's four separate value rows — four regions at eight rows apiece
  is a section nobody can see the end of), with Add Region and "Place on
  Canvas" in the footer, both disabled at the cap. It is the filter
  stack's idiom, not the spotlight's: there is no on/off checkbox because
  an empty list IS off, and the whole array goes back through one
  `set_video` patch. "Place on Canvas" arms §4.2's region mode and
  APPENDS what is drawn — one button for the section rather than one per
  row, because the inspector's command seam carries a selector and no
  index. Stored regions are not drawn on the canvas outside that mode: a
  blurred region is self-evident on the picture, unlike a spotlight's
  geometry, and drag handles for one are a hit-test family the frozen
  canvas file has no room for yet.
- Format version 8: *Motion* — In and Out (a kind from the nine
  entrances/exits, or None, each with a duration in seconds), During (a
  kind from the five continuous motions, or None, with Amount % and
  Period — Period disabled for Drift, which ignores it) and a Preview
  button that sets the in/out range to the clip, turns Loop on and plays.
  Shut by default, after Obscure. Every write is one `set_video` per clip,
  so each clip keeps its own other slots, and it lands on the base props
  even inside an action, since motion is not an animation target. Also
  Clip ▸ Motion ▸; the timeline's name strip draws the in/out wedges and a
  During glyph.

**Audio sections** — clips whose media has an audio track and whose audio
is enabled.

- Volume % (0–400, dB shown), Mute, and **Normalize** — one press sets the
  clip's volume so its own loudest moment lands at −1 dBFS, measured from
  the waveform cache over the source window that actually plays. It
  REPLACES the volume rather than multiplying it (so pressing twice changes
  nothing), writes the clip's BASE volume even when the playhead is inside
  an action, leaves `muted` alone, and gives each clip of a selection its
  own gain. A clip quieter than about −13 dBFS cannot reach −1 through the
  model's 4× ceiling: it is normalised as loud as it goes and the result
  says where it landed. Also Clip ▸ Normalize.
- Fade in / fade out in seconds (also the corner handles on the clip).
- Ducking: "lower other audio to N % while this clip plays", with
  attack / release. a screencast editor's rule: for the whole clip extent, not
  voice activity. Realised as volume ramps folded into the other clips'
  envelopes by the core.
- Mix to mono — a fold, not a gain, so it is sample work like the three
  below and lives with them at the head of the tap's Mix stage (§7.2). It
  averages EVERY channel of the composition track and writes the average to
  all of them, and it is inert below two channels. Detach Audio (⌥⌘D; also
  Clip menu).
- Volume actions share the Actions table.
- M3 — Pan, "Smooth volume levels" (compressor), "Remove background
  noise". Unlike everything above, these three — and Mix to mono, which
  joined them in road map 2's phase 5 — cannot be a gain curve, so
  they are not folded into the core's envelope: they are sample work, done
  in Swift by one `MTAudioProcessingTap` per composition audio track, and
  the SAME tap serves the preview and the export (the mix reaches both
  `AVPlayerItem.audioMix` and `AVAssetReaderAudioMixOutput.audioMix`, and
  taps were measured to run on each). A track no clip of which uses them
  gets no tap and is bit-identical to before they existed — on an EXPORT,
  which is where that promise is worth something. A preview build made for
  the level meter (§4.4) taps every audio track, inert ones included,
  because a meter that lights only on the tracks carrying a compressor is
  worse than none; there is no file there to be identical to.
  - Pan is a balance: one gain per channel, constant power across the
    sweep and unity at the centre, so 0 is exactly a bypass and a hard
    pan is +3 dB in the channel it goes to. Inaudible on a clip whose
    source is mono — the widening to stereo happens after the tap. **On a
    clip that also asks for Mix to mono it is a TRUE pan**, because the
    fold runs first and both channels then carry the same signal; that
    ordering is forced rather than chosen, since folding AFTER a pan is
    algebraically a gain change — `(g_L·x + g_R·x)/2 = ((g_L+g_R)/2)·x` —
    and would make the pan control read as broken.
  - The compressor is a channel-strip insert on the track, ahead of the
    fader: its envelope carries across a cut and the volume, fades and
    ducking apply after it. Its attack and release are ticks in the
    schema but sub-frame, and the pane shows them in ms.
  - Noise reduction is a short-time spectral attenuator over a noise
    floor tracked from the clip itself — not a gate, and it delays the
    track it runs on by 512 samples (10.7 ms at 48 kHz).
  - Read at the clip's BASE properties, never through an action, exactly
    as ducking is (§7.2).

**Text sections**

- Content (multi-line), font family / style / size, color, alignment
  (left / center / right and top / middle / bottom within the box), line
  spacing, letter spacing.
- Outline (width, color); Backdrop (fill, opacity, padding, corner
  radius); Shadow (shared section).
- Box: auto-size, or fixed width with wrapping.
- Animation on position / opacity / scale is Actions, like every other
  property. The built-in REVEALS are their own thing and are
  `text.animation` (format version 5): an *Animation* section of three
  controls — a kind popup (None, Typewriter, Word Fade, Line Rise), In and
  Out — written through `set_text` as one whole object, which is the SECTION
  saying all three controls and not a rule about patches: a patch of a nested
  object merges key by key (§5.2, §6), so an agent may send `animation` with
  one key in it and keep the other two. In and Out are DURATIONS measured
  from the clip's own first and last frame, not times.
  The section cannot show the reveal's PROGRESS, and deliberately does not
  try: how far along a reveal is, is a fact about the frame under the
  playhead rather than about the clip, and the core computes it per frame
  into the recipe (§7.3) so the preview, `render_frame` and an export
  cannot disagree about it.
- Presets: Title, Subtitle, Lower third, Caption — set face, size,
  backdrop and position in one click.

**Shape sections**

- Kind: rectangle, rounded rectangle, ellipse, line, arrow. Stroke width
  and color, fill color and opacity, arrowheads at start / end, corner
  radius, Shadow.
- Format version 6: *Gradient* — a Kind popup (Linear, Radial), an Angle
  row disabled for Radial, the stop list as an at-and-colour row apiece
  with Add and Remove, and a Reset that sends `{"gradient": null}` and so
  brings the flat fill back. Every row is DISABLED for `line` and `arrow`,
  which have no area to fill and keep their stroke colour — the field is
  still stored and range-checked on them (§5.2), exactly as `radius` is on
  every kind. Every key of `gradient` is re-sent on every write, which is the
  SECTION knowing all of them rather than a rule about patches: a patch of a
  nested object merges key by key (§5.2, §6), so an agent may send `gradient`
  with one key in it and keep the rest — and a `stops` LIST it sends replaces
  the whole list, which is why the row's Add and Remove re-send every stop.
- M3: *Spotlight* — which darkens the canvas outside a rectangle or
  ellipse, with an optional 1.2–2× zoom of the region — is a
  `video.spotlight` prop and appears in the **Video** pane, not here.

**Media tab** — a 38 pt action row (Add Media…, its ⇧⌘I hint, a right-aligned
item count), a 60 pt **find band**, the list, then a 40 pt footer holding
Consolidate… and a line saying what it does.

- The find band is two lines: a search field across the top (name contains,
  case- and diacritic-insensitive, as you type), then a Sort popup — **Import
  Order** · Name · Duration · Kind — and an "Unused only" switch. It is two
  lines rather than one because the three controls measure 319 pt against the
  284 the panel leaves at its default width. The row spells "Import Order"
  and not "Added" because nothing records when a file arrived: `Media` has no
  timestamp, and what exists is the array's own insertion order, which is
  also ascending id order for any project built by ops. The action row's
  count becomes "N of M items" while anything is narrowing.
- None of the three is persisted, and the band never rebuilds the pane: the
  rows it already built are hidden and re-ordered in place, because
  `InspectorPaneView.rebuild()` destroys the field editor and the caret with
  it. A search is an act of finding, not a preference.

- Every imported file as a 52 pt row: a 34 × 38 pt thumbnail, the name at
  12 pt, a mono 10 pt meta line of duration, dimensions and fps, an
  audio badge, a "missing" badge. Add Media… (⇧⌘I); drag files from the
  Finder onto the panel, the canvas, or the timeline.
- Drag from the list to a timeline track (drops at the cursor) or onto
  the canvas (appends on a new top track at the playhead).
- Right-click: Reveal in Finder, **Reveal in Timeline**, Relink…, Remove
  (refuses while in use and offers "Remove and delete its clips"). Reveal in
  Timeline selects the clips whose source is that file and scrolls the
  timeline to the earliest of them; it is disabled for a file whose only
  users are INSIDE a nest, because the selection holds top-level clip ids
  alone. "Is this file used" is one question with one answer
  (`MediaUsage.swift`), and it walks the nests the way the core's
  `every_clip()` does — Remove and the `remove_media` tool ask it too.
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
- File ▸ Generate Captions… (road map 2's phase 4)
  makes the same clips out of SPEECH, on this Mac: a sheet picks the
  language and the scope (the selection, the in/out range, or everything
  with sound), and the same card becomes its own progress bar while it
  runs. It transcribes each clip's own source window, extracted to a
  temporary audio file — never the media file as it sits, and never the
  whole of a long recording for the sake of a short clip. macOS gates
  speech recognition behind a grant, and this sheet is the one place the
  app asks for it. Recognition stops after about a minute per clip, which
  is the framework's own ceiling: when it does, the run SAYS where it
  stopped rather than presenting a truncated transcript as the whole of
  what was said. Cues are at most two lines of 42 characters, at most six
  seconds, with at least a frame between them.
- File ▸ Export Captions… writes one track of text clips back out as
  SubRip (`.srt`) or WebVTT (`.vtt`) — the clips' own times and words, so
  a caption retimed by dragging exports where it was dragged to. The track
  is never guessed: a candidate is a track whose clips are ALL text, and
  with none or with more than one the command names the candidates and
  offers a popup instead of choosing. A cue written out and read back in
  lands on the TICK it left, at every ordinary frame rate: `format_timecode`
  rounds to the nearest millisecond, which is at most 300 ticks, and half a
  frame is 10,000 ticks even at 30 fps, so the snap on the way back in can
  only find the frame the cue came from. What is not exact is the FILE.
  Import snaps every cue to the frame grid, so a source whose times are off
  that grid comes back written onto it — at 30 fps `00:00:04,120` returns as
  `00:00:04,133` — and byte identity with the file you imported needs cue
  times already on the grid AND a frame that is a whole number of
  milliseconds, which is 25 or 50 fps.

**Document tab** — a summary group first (Resolution, Frame rate, Duration,
Tracks, Background as read-outs on an 86 pt label column), then the editable
groups below it.

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

A bar, the ruler (22 pt), then the lanes. Track headers (132 pt) on the
left scroll vertically with the lanes; ruler and lanes scroll horizontally
together (one `NSScrollView` whose document view draws everything; the
header column and ruler are floating subviews pinned in `scroll(_:)`).

**Timeline bar** (36 pt, `BarView(border: .both)`), left to right:

- A **selection block** at the left edge that never moves, minimum 176 pt:
  an 8 × 20 pt tint chip in the clip's kind colour, the name at 11 pt
  semibold over `Track V1 · video` in mono 9 pt. With nothing selected, a
  `DS.borderStrong` chip and "No selection"; with several, the count. It is
  the same `ClipKindStyle` mapping the inspector's header and the clip's own
  name strip use.
- **Clip actions**, `GhostButton`s at 28 × 24 pt with 17 pt symbols: Split
  (⌘T), Trim Start (W), Trim End (E), Ripple Delete (⌘⌫), Add Marker (M),
  Duplicate (⌘D), Add Text (T), Add Shape. The last four came down from the
  window toolbar. Add Shape is here rather than nowhere because it has no
  menu item anywhere in the app.
- **Snap** (N), then the **output level meter**, then the zoom cluster —
  minus, the slider, plus, Fit (⇧Z) — and the **S / M / L** track size.

**The level meter** (road map 2's phase 5, `LevelMeterView`) is a
120 × 12 pt two-channel meter in the flexible gap left of the zoom cluster:
a peak tick over an RMS fill per channel on a −60…0 dB scale, with a clip
cell at the right end that is the one place the bar spends coral. It sits
there rather than last so that nothing which shipped moves at any window
width, and it carries no divider — the row's fixed content is 880 pt
against a 900 pt minimum window, and a divider's gap and hairline would
overrun it. Starved below 40 pt it draws NOTHING, the selection block's own
rule. It shows the MIX, not a track, which is why it is not in a track
header; it is fed while the transport is moving and falls to silence when
it stops, and at rest it is one fixed appearance (which is what lets the
offscreen harness photograph it). The number it draws is the DSP tap's
measurement times the plan's envelope at that instant — §7.2's "a peak is
pre-fader" rule, the same one `detect_silence` uses — because a
composition track has exactly one `audioTapProcessor` and a second,
post-fader tap cannot be built.

**Track size** picks a ROW of lane heights and a track's KIND picks the
column: text 30 / 44 / 58, video 54 / 84 / 116, audio 40 / 60 / 82. A track
holding nothing but text and shapes is a text track; one whose every clip
sings and none of which draws is an audio track; everything else, an empty
track included, is video. At S a clip is its name strip and little else,
which is intended.

**Ruler**: adaptive ticks (frames → seconds → 10 s → minutes as you zoom).
The playhead head is a coral triangle you drag to scrub; clicking the
ruler moves the playhead. I / O set an in/out range at the playhead
(shaded on the ruler and lanes, ⌥X clears); the range scopes playback
loops, ripple-delete-range, and export. Markers are small flags, chapter
markers filled; double-click to rename; drag to move.

**Tracks**: header shows the name (double-click to rename), eye (hide
video), speaker (mute), lock, and — format version 3 — headphones (solo: a
fourth toggle at the same pitch, whose rule is §5.2's; `S` is its text
fallback, as H, M and L are the other three's, drawn only when the SF
Symbol is missing). Top track is front-most. Drag a header to
reorder. Dragging a clip above the top track or below the bottom one
creates a track; Track > Remove Empty Tracks cleans up. New Track is ⇧⌘N.

**Clips are objects, not bands.** A clip is a 4 pt-rounded body inset 3 pt
from the lane's top and bottom, clipped to that shape, with a 1 pt
`rgba(white, 0.14)` border — so you can see where one ends and the next
begins, which was the whole complaint.

- **Name strip**: 16 pt along the top, `rgba(black, 0.26)` over the tint,
  6 pt padding, an 11 pt kind symbol at 62 % white, then the name at 10 pt
  semibold, 92 % white, truncated with an ellipsis. The symbol is the point
  of it — a clip's kind used to be invisible. A labelled clip (§5.2)
  carries a 6 pt dot in its label's colour at the strip's right end, the
  name giving up 11 pt for it; the tint stays the KIND's, never the
  label's. A double-click on the clip opens a rename field over the strip.
- **Tint by kind**, `ClipKindStyle`: video slate, audio green, still violet,
  text amber, shape teal, nest grey. A `media` clip is video or audio by
  whether its FILE has pictures, not by `enabled.video` — that flag is the
  Detach switch, and reading it made every imported mp3 draw as video.
- **Video body**: filmstrip thumbnails at a fixed 34 pt tile, 72 % opacity,
  with the clip's tint washed back over them at 54 % so the clip still reads
  as one tinted object rather than a strip of photographs.
- **Audio body**: waveform at `rgba(white, 0.44)`, symmetric about the
  body's centre. Muted draws at 40 %.
- **Selected**: a 2 pt coral ring, plus 6 pt `rgba(white, 0.38)` trim grips
  at both ends — on the selected clip only, and only where the clip is wide
  enough and its track unlocked for a trim to be possible, so a grip never
  offers what a click cannot take.
- An action is a darker band under the name strip over its span. A
  **transition** is the overlap zone, drawn above both bars: a 45° hatch at
  `rgba(white, 0.26)`, 3 pt on a 7 pt perpendicular period, with a solid
  edge down each side, and its kind named only when the word fits. Locked
  track: hatched overlay. Fade handles are small squares at the audio
  corners you drag inward.

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
- Marquee-select from any empty timeline space — a lane's gap, the strip
  under the ruler, or the room below the last lane, which with two tracks
  is most of the pane — across tracks, skipping locked ones; a bare press
  clears the selection first and ⇧ keeps it. ⇧-click adds; ⌘A selects
  all; ⌥⌘A selects everything after the playhead (then drag to insert
  time).
- ⌘T splits the selected clips at the playhead, or every unlocked clip
  under the playhead when nothing is selected.
- W / E trim the selected clip's start / end to the playhead.
- ⌫ deletes and leaves a gap. ⌘⌫ ripple-deletes.
- ⇧⌘F freeze frame at the playhead.
- Detach Audio (⌥⌘D).
- Transitions: the Transition section for kind — Cross Dissolve, Fade
  through black / white, Push (4 directions), Wipe (4 directions), Slide,
  Zoom — its curve, its audio crossfade and its duration. Changing the
  duration moves the later clip to match. Clip ▸ Transition ▸ does the
  same for a selection, and at a HARD CUT it MAKES the overlap first
  (`add_transition`, half a second centred) out of the two clips' unused
  handles, so nothing else on the timeline moves; a clip at a gap is
  skipped rather than refused, and None stays available for any selection
  because a clip can carry a stored transition the timeline does not draw.
  Double-clicking a clip renames it, or opens a nest — it has never set a
  kind.
- Nest (⌘G): the selected clips collapse into one grey clip standing for
  the group, which then moves, trims, fades and transforms as one thing;
  the new clip is selected. Un-nest (⇧⌘G) opens every nest clip in the
  selection and selects what came out, in one undo step.
- **Entering a nest**: double-click a nest clip, Clip ▸ Open Nest (⌘↓) or
  ⌘↑ to come back out. The timeline shows the nest's own tracks and clips
  at the nest's own zero, the canvas shows it at its frozen size with the
  outer transform NOT applied — a compound clip is edited on its own
  terms — and a breadcrumb in the corner over the track headers leads back
  out ("Timeline › Intro", the last two levels middle-truncated with the
  full path as its tooltip, and clicking it is ⌘↑). Every edit works in
  there unchanged: the op carries the envelope's `scope` (§6), which is a
  nest id, and the core applies it to a VIEW project whose top level is
  that nest (`core/src/scope.rs`) and returns a whole document, so undo
  stays one stack of parent handles and one edit is still one step.
  Entering and leaving are view state — no undo step, no dirty mark — and
  the playhead maps in and out (`t − nest_clip.start`, the whole mapping:
  a nest has no speed and no in point), so the frame under it does not
  move. Leaving re-selects the nest clip.
  Four things are true in there and are not obvious. Seven ops have no
  meaning inside a nest and the core refuses a scoped one by name — the
  three marker ops, `set_canvas` and the three media ops — so the app
  sends those UNSCOPED instead, which is why File ▸ Add Media…, a Relink,
  a Remove and the Document tab go on working with a nest open, while the
  three MARKER commands are turned off (a nest has no markers, and the
  playhead in there is measured from the wrong zero for one). The in/out
  range is cleared on the way in and on the way out, because a pair of
  ticks means one thing inside a nest and another to an export. A scoped
  edit has a WIDER refusal arm than any other: the clip and track caps and
  the nesting depth are document-wide and invisible from inside, so an op
  can be valid against the nest and still come back `too many clips`. And
  a nest clip gives up rename-by-double-click, keeping ⇧⌘R, Clip ▸
  Rename… and the Clip tab's header field.
  The round trip — ⇧⌘G, edit, ⌘G — still works and is still the identity
  on clip content; what it costs and going inside saves is the nest clip's
  own transform, opacity, fades and volume.
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

### 5.2 Project — the JSON schema (format version 8)

The Rust value, serialized by serde. Small, no pixels. All times are
ticks, all positions canvas pixels, colors `[r, g, b, a]` floats 0–1 — FOUR
numbers, never a three-element form and never clamped, with
`video.chroma.key` the one `[r, g, b]` in the schema — angles degrees,
opacity/volume 0–1 (volume may exceed 1, up to 4).

**What a PATCH against this schema means**, once for every op that takes one
(§6's five `set_*`, `add_text_clip`'s `text`, `add_shape_clip`'s `shape` and
an action's `end`): it **merges key by key at every depth** — a nested object
merges into the stored one rather than replacing it, so `{"shadow":
{"blur": 40}}` keeps the colour and the offset — a key set to **`null`
clears** that key (in an action's `end`, where the patch IS the stored
value, it removes the key, which is the same act one level up), and an
**array replaces** its whole list. A key or a value the vocabulary does not
have is refused by its dotted path, array indices included, and never
dropped or corrected (§6, `core/src/patch.rs`,
`CONTEXT.md`'s **Patch**). The FILE reader is the lenient one and stays so:
it opens what a newer build wrote (§5.6).

```json
{
  "version": 8,
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
    { "id": 1, "name": "Track 1", "hidden": false, "muted": false, "locked": false,
      "solo": false }
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
                 "filters": [], "reflection": null, "spotlight": null,
                 "obscure": [], "blend": "normal", "motion": null },
      "audio": { "volume": 1.0, "muted": false, "fade_in": 0, "fade_out": 0,
                 "duck": null, "mono": false, "keep_pitch": true,
                 "pan": 0, "compressor": null, "noise_reduction": 0 },
      "text": null, "shape": null,
      "actions": [
        { "id": 1, "start": 2400000, "duration": 900000, "curve": "ease_in_out",
          "end": { "video": { "scale": 0.6, "x": 520 } } }
      ],
      "transition_in": null,
      "name": null, "label": null }
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
- `video.obscure` (format version 4): an ordered list of regions that HIDE
  what is under them — a face, a password field — each
  `{ "shape": "rect" | "ellipse", "x": 0, "y": 0, "width": 480,
  "height": 270, "feather": 20, "kind": "blur" | "pixelate",
  "amount": 1.0 }`, at most **four**, a shader budget exactly as
  `video.filters` is: the uniform block carries four regions and a fifth
  would be a control that hides nothing. Every value spelled there is what
  an omitted key takes, `shape` defaulting to `rect` and `kind` to
  `pixelate`. The box is the spotlight's own, so the two region controls
  put the same rectangle on screen; the kind and the amount are the
  opposite of a filter's half-strength blur, on purpose. A filter has to be
  visible without destroying the frame, while a region that only half hides
  has failed at its one job, and a blur at the shader's maximum radius is
  soft enough to read a large password field through — so the default is
  the kind that actually hides. `shape` is the spotlight's `SpotShape`, the
  same two shapes spelled once (`model_regions.rs`); `kind` is a closed
  vocabulary of its
  own and not a narrowed filter kind, so a hand-written `"sepia"` is
  refused on the way in rather than clamped later. The geometry is
  §5.3's source-pixel frame, so a region rides with its layer through
  scale, move and rotation; `amount` maps to the same maxima the blur and
  pixelate filters use. Where two regions cover one pixel the GREATER
  hiding wins and the other is not applied at all — a length in source
  pixels times the mix it would be applied at, a tie going to the pixelate
  — because both are a fresh sample of the raw picture and applying the
  second would put back what the first destroyed; adding a region can never
  make a frame less hidden, and a region at `amount` 0 is there and changes
  nothing. Written through `set_video` like any other video
  property — there is no obscure op.
- `video.blend` (format version 6): how this layer COMBINES with what is
  already on the canvas — `normal`, `multiply`, `screen`, `add`,
  `overlay`, `darken`, `lighten`, `difference`, a closed vocabulary
  refused by serde on the way in. `normal` is source-over and the default,
  which is what every project drew before the key existed, so an absent
  key, a zeroed uniform block and a recipe from an older core all mean the
  same picture. **The declaration order in `model_props.rs` is a
  contract** — it is the shader discriminant, as `ObscureKind`'s is, and
  `normal` is 0 with no `+1` offset, because a layer has exactly one blend
  mode and there is no empty slot to reserve. A mode may be added at the
  end; the eight may not be reordered. It belongs to the LAYER and not to
  a source kind: media, image, still, text and shape all draw through one
  fragment stage, so all five blend. Two rules are not in the schema and
  are stated where they hold — a clip mid-TRANSITION always draws
  `normal`, which the CORE forces into the recipe (§7.3), and a NEST clip
  may not carry a blend at all, which is an op's refusal
  (`edit_props.rs`'s `check_blend`) rather than a vocabulary one, since
  the value is legal and it is the clip that refuses it. A blend on a clip
  INSIDE a nest is allowed, and §5.3 records what it blends against.
- `video.motion` (format version 8): `null`, or up to three preset SLOTS —
  `{"in": {"kind", "duration"}, "out": {…}, "during": {"kind", "amount",
  "period"}}`. `in` and `out` are one of nine edge kinds (`fade`, `zoom_in`,
  `zoom_out`, `slide_left`, `slide_right`, `slide_up`, `slide_down`, `spin`,
  `pop`) over a DURATION measured from the clip's first and last frame,
  `text.animation`'s convention; `during` is one of five (`pulse`, `shake`,
  `spin`, `bounce`, `drift`) over the whole clip, `amount` 0–1 and `period`
  one cycle in ticks, which `drift` ignores. Both enums are closed and
  refused by serde on the way in; neither declaration ORDER is load-bearing,
  unlike `BlendMode`'s, because nothing crosses to a shader. Every field
  defaults, `null` being a clip that sits where it is placed, so an absent
  key means what every project meant before it existed.
  **It is not a value the compositor reads.** A preset says what a clip
  DOES, and the core turns it into PLACEMENT at render time (§5.3, §7.3) —
  the recipe publishes no `motion` key at all, and everything that EDITS
  rather than draws reads the clip un-moved (§5.4). Three rules are not in
  the schema and are stated where they hold: a `Motion` whose three slots
  are all null is NORMALISED to `null`, by the patch path and by the split
  rule, so one clip has one spelling of "no motion"; `in + out` longer than
  the clip scales both down to meet rather than refusing, because "too long
  for THIS clip" is a fact about a clip and a later trim would invalidate a
  refusal anyway; and a copy op decides which slots it may carry, since a
  preset is anchored to a clip's two ends and a copy has new ones (§6, and
  road map 5 §5e's table). The range checks are `props_check.rs`'s — both
  durations ≥ 0, `amount` 0–1, `period` at least one tick — and the ticks a
  PATCH carries ARE snapped by the core, after those checks, so a refusal
  names the number the caller sent (§6's preamble; `period` floors at one
  FRAME rather than at the nearest grid point, because it divides in every
  `during` formula and has no zero). `text.animation`'s two timings are
  snapped the same way. A FILE is not snapped: it opens as what it says.
- `audio.duck`: `{ "level": 0.2, "attack": 300000, "release": 600000 }`.
- `audio.pan` (M3) is -1 (hard left) to +1 (hard right);
  `audio.noise_reduction` (M3) is 0 (off) to 1.
- `audio.mono` has been in the schema since M1 and was IGNORED until road
  map 2's phase 5: it is a fold, not a gain, so it belongs with pan and the
  compressor in the tap (§7.2) rather than in the plan, and nothing folded
  it there. It now averages every channel of the composition track into all
  of them, at the head of the Mix stage. No migration and no version bump:
  the key already existed and already defaulted false, so only a project
  that had deliberately set it changes — and changes to what it always
  asked for.
- `audio.compressor` (M3): `null` or `{ "threshold_db": -18, "ratio": 3,
  "attack": 6000, "release": 120000, "makeup_db": 0 }` — "smooth volume
  levels". Unlike ducking, this cannot be expressed as a gain curve, so
  the model carries the parameters and the DSP is Swift's.
- `text`: `{ "content": "…", "font": "SourceSans3-SemiBold", "size": 72, "color": [...],
  "align": "center", "valign": "middle", "line_spacing": 1.0, "tracking": 0,
  "outline": null | { "width": 2, "color": [...] },
  "backdrop": null | { "color": [...], "padding": 12, "radius": 8 },
  "width": null | 800,
  "animation": null | { "kind": "typewriter", "in": 600000, "out": 0 } }`.
- `text.animation` (format version 5): how the words ARRIVE and how they
  LEAVE, or `null` — the common case — for text that is simply there for
  the length of its clip. `kind` ∈ `typewriter`, `word_fade`, `line_rise`,
  a closed vocabulary like `video.obscure`'s `kind` and refused on the way
  in if it is anything else, because each one is a different drawing
  routine and there is no neutral reveal to fall back to. `in` and `out`
  are DURATIONS, not times: the reveal runs for `in` from the clip's own
  first frame and the un-reveal for `out` back from its own last one,
  either of them 0 for "that end does not happen". An animation that says
  nothing is a one-second typewriter that does not un-reveal.
  Both halves measure against the CLIP's own duration, never the visible
  span of the instance drawing it, which is the rule clip time already
  follows (§7.3) — a nest clip's edge cuts a nested caption off mid-reveal
  rather than making it un-reveal early. `in + out` longer than the clip
  does not refuse: the reveal is the smaller of the two ramps, so a short
  clip shows a partial reveal — and keeps ONE phase for the whole of its
  life, which §7.3 argues — and nothing has to be clamped to a length a
  later trim could change. There is deliberately no curve field — the
  shape of the motion is in the kind, and easing between two arbitrary
  values is what actions are for (§5.4) — and no per-frame number: the
  core computes that into the recipe (§7.3), so the model says what the
  animation IS and nothing about where it has got to.
- `shape`: `{ "kind": "arrow", "width": 320, "height": 120,
  "stroke": { "width": 6, "color": [...] }, "fill": null | [...],
  "arrow_start": false, "arrow_end": true, "radius": 0,
  "from": [0, 1], "to": [1, 0], "gradient": null }` — `from`/`to` are unit
  coordinates in the box, for line and arrow only.
- `shape.gradient` (format version 6): `null` — the common case — or
  `{ "kind": "linear" | "radial", "stops": [{ "at": 0..1,
  "color": [r,g,b,a] }, …], "angle": 0 }`, drawn by
  `LayerRenderers.renderShape` with `CGGradient` and taking precedence
  over `fill` while it is non-null. **Setting one does not clear `fill`**:
  both persist, so `{"gradient": null}` is an exact inverse — the
  section's Reset brings the colour back out from under it — and the
  precedence rule stays in one statable place instead of becoming a side
  effect of whichever op wrote last. Between **2 and 8 stops**
  (`MAX_GRADIENT_STOPS`), named rather than trimmed: one stop is a solid
  and `fill` already spells that, and the ceiling is 8 where
  `video.filters`' and `video.obscure`'s are 4 because those two are
  SHADER SLOTS — the uniform block carries exactly four of each — while a
  gradient is drawn on the CPU, where nothing downstream has slots at all.
  `angle` is degrees from the RIGHT, counter-clockwise (`video.shadow`'s
  convention, the crate's only one); it is meaningless for `radial` and is
  stored and range-checked there anyway, so flipping the kind and back
  does not lose it. `{"gradient": {}}` is the type's own default — linear,
  angle 0, black at 0 to white at 1 — which is the feature's first
  impression and is what the inspector's Add sends.
  **The stops are deliberately NOT checked for order.** `CGGradient`
  requires monotonic locations or its output is undefined, so a refusal
  looks like the tidy answer; it has a failure mode nobody would accept,
  because dragging one stop past another is how a gradient is edited and
  the drag would stop working half way through. `video.filters` is the
  precedent — an ordered list the core does not police — and the fix
  belongs where the requirement is, so the RENDERER sorts before it draws.
  The question is a RENDER-time one and only that: `shape` is not among
  the groups an action's end patch may carry (§5.4), so no gradient is ever
  interpolated and an unsorted stop list is only ever drawn.
  `line` and `arrow` have no area and IGNORE a gradient entirely — stored,
  range-checked, not drawn, with the inspector's rows disabled for them,
  which is exactly `shape.radius`'s precedent (every kind carries it, only
  the rectangle reads it). Refusing it per kind would mean the kind popup
  had to clear the field on its way past, and a value a popup deleted is
  work nobody can get back.
- `actions[].end` is a patch: any subset of `video`, `audio`, `text` keys.
  `curve` ∈ `linear`, `ease_in`, `ease_out`, `ease_in_out`.
- `transition_in`: `null` or `{ "kind": "cross_dissolve" | "fade_black" |
  "fade_white" | "push_left" | "push_right" | "push_up" | "push_down" |
  "wipe" | "slide" | "zoom" | "wipe_left" | "wipe_up" | "wipe_down",
  "curve": curve, "audio": bool }`. Its duration *is* the overlap with the
  previous clip on the track; a clip with no overlap ignores it. `wipe` is
  the original rightward one and the three directions beside it are
  **version 7**'s, appended; `curve` (version 7, default `linear`) eases the
  progress the compositor is handed, and `audio` (version 7, default
  `false`) crossfades the two clips' sound across the overlap at constant
  power. Both defaults are the FILE's and deliberately differ from what the
  core MINTS — every transition an edit makes from version 7 on says
  `ease_in_out` and `audio: true` (§11, R5-2), so a project written before
  the keys existed looks and sounds exactly as it did.
- `name` (format version 3): the clip's own name, or `null` — the common
  case — meaning "call it what it shows": the app falls back to the nest's
  name for a nest clip, the media file's name where there is one, else the
  kind (`ProjectSnapshot.name(of:)`, the one fallback the name strip, the
  selection block and the Clip tab header all read). `set_clip` stores it
  trimmed; the schema keeps whatever it is given.
- `label` (format version 3): `null`, or a colour NAME from the marker
  vocabulary — `red`, `orange`, `yellow`, `green`, `blue`, `purple`, the
  one list, spelled once on the app side (`ClipLabel.swift`) and drawn as a
  6 pt dot on the clip (§4.4). Stored unvalidated, exactly like a marker's
  `color` and for the same reason: a build that policed the list would
  refuse a project written by a newer one, so an unknown name is kept and
  drawn in the neutral ink.
- `tracks[].solo` (format version 3): while any track in a container's
  track set — the timeline's, or one nest's own — is soloed, every track
  in that set without `solo` is treated as muted; mute wins, so a track
  that is both muted and soloed stays silent. Audio only — it hides
  nothing — and per container, so a nest's own tracks are judged among
  themselves. The rule is on the set, not on what plays: a soloed track
  with nothing audible on it still silences the rest (§7.2).
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
- **Every region in the model is in that one frame** — each entry of
  `video.obscure` (format version 4) and the rectangle `add_zoom_action`
  (§6) is given, as well as the spotlight's box. `x`/`y` are the region's
  **CENTRE**, an offset in source pixels from the centre of the cropped
  rect, and `width`/`height` its size in the same pixels; the field names
  say neither, so both the op table and the core say it in words. One
  frame is what lets a region drawn on the canvas, a region typed into the
  inspector and a region sent over MCP mean the same rectangle, and it is
  why `Spotlight`, `ObscureRegion` and the `SpotShape` they share sit in
  one module (`model_regions.rs`, §7.10) rather than beside the fields
  that hold them.
- **`reflection` hangs below the layer** (M3), mirrored about the cropped
  rect's bottom edge, `gap` source pixels clear of it, `height` of the
  layer's cropped height tall, fading out with `falloff`. It is drawn
  BEFORE the layer, so the layer always wins where they meet, and it is
  part of the layer — it rotates with it.
- **`video.motion` is the second recipe-only term** (format version 8, spec
  §11's R5-4; a transition's progress is the first). It is a PRESET and not
  a placement: `motion.rs` turns it into a scale, a rotation, an opacity and
  an offset at render time, and `recipe.rs` folds those into the five placed
  fields of the layer it publishes — so the recipe carries no `motion` key
  and the compositor never hears of one. The container a slide measures
  itself against is the canvas the clip is placed in, the enclosing nest's
  frozen one inside a nest; the pivot is the layer's VISIBLE centre, so a
  zoom on a cropped layer does not drift; the total rotation is reduced
  `rem_euclid(360)`, so a whole turn is exactly no turn; and for TEXT, whose
  size the model cannot know, a slide starts half a canvas beyond the edge,
  which clears any text narrower than it. A clip with no active slot is
  returned UNTOUCHED rather than moved by an identity, because `x + b − b`
  is not `x` in floats and the frame at the end of an arrival has to be
  byte-identical to the same clip with no preset at all.
- **A nest's layers are flattened at evaluation time** (M3): each drawing
  clip inside a nest becomes one recipe layer with the nest clip's
  transform folded in (scales multiply, rotations add, offsets rotate),
  and every such layer carries the nest's canvas rect as its `clip_rect`
  (§7.3). Fold and clip are both similarity transforms, so the
  composition is exact and no intermediate render target is needed.
  Four honest limits fall out of the flattening, and `video.blend` (format
  version 6) is what got the last two written down — the fourth arrived
  with it, and the third had been true since M3 with nothing recording it.
  A nest clip's `opacity` multiplies each inner layer separately rather
  than fading the group as one picture; only the innermost `clip_rect` is
  carried; **a nest clip's own PER-PIXEL properties reach no layer at
  all** — its filters, colour controls, chroma key, shadow, reflection,
  spotlight, hidden regions and blend, because `recipe.rs::layer` reads
  every one of those off the INNER clip and a nest clip never becomes a
  layer; and **a blend on a clip INSIDE a nest blends against the canvas
  below the WHOLE nest**, not against the nest's own layers under it,
  because there is no offscreen composite of the nest for it to meet. All
  four are the same fact read four ways — there is no such thing as "the
  nest's picture" — and the answer to all four is the offscreen pass the
  flattening exists to avoid. Two ops refuse rather than let the third be
  silent: the nest CLIP is refused a blend outright (§5.2, §6) and
  `add_blurred_background` refuses a nest clip, whose copy would come out
  sharp. The rest are allowed and recorded instead, because a clip inside
  a group is still a layer of its own and the common case — a group over
  one backdrop — draws exactly what the popup promises. `nest.rs`'s
  `Frame` doc carries the same four.

### 5.4 Actions

`Action { start (clip time), duration, curve, end: Patch }`. To evaluate a
property at clip time *t*: start from the clip's base props, apply the end
patch of every action that finished at or before *t* (in start order),
then if *t* is inside an action, interpolate from that state to the
action's end patch along its curve. Numeric fields interpolate; colors
interpolate per channel; booleans and strings switch at the end. Actions
on a clip may not overlap (`add_action` refuses). Video, audio and text
properties all go through the one list with typed patches.

**Lists interpolate per index** when the two sides are the same length and
each pair of entries agrees on the keys that say WHAT the entry is — a
filter's `kind`, a region's `kind` and `shape` — and switch at the end
otherwise; the hold is per entry, so a list in which one region changes
shape still interpolates every region beside it. That is the crate's rule
and not one list's (`actions.rs`), so `video.filters` and `video.obscure`
are both governed by it with no code of their own. The wider set of
discriminants is deliberately confined to list ENTRIES: in a list an
entry's only identity is its index, so a changed `shape` gives no way to
tell a reshaped region from a replaced one, while `video.spotlight` is one
named object whose `shape` is a property of it — an action that moves that
spotlight from a rect to an ellipse still interpolates its geometry, as it
always did.

The object rule is why `text.animation`'s discriminant is spelled `kind`
(format version 5): an action from a typewriter to a line rise switches at
the end, where an action between two typewriters of different lengths
interpolates their `in` and `out`. That second one is legal and rarely what
anybody wants — the two numbers are the animation's own timebase, so
sliding them mid-reveal moves the ground under it — which is a caution, not
a rule the ops enforce.

**`video.motion` is NOT an animation target** (format version 8). A preset is
anchored to the clip's two ends and an action is a ramp between two states,
so there is nothing to interpolate — half a slide into half a spin is not a
picture anybody asked for — and the evaluator would put the base value back
anyway, leaving a control that reported success and did nothing. So
`set_action_end` refuses a patch whose `video` object names `motion`, by
name — the one refusal that is about the OP rather than about the
vocabulary, since the patch is otherwise walked like any other; and
because a hand-written file, a pasted action or a project from another tool
reaches evaluation without passing the op, `evaluate_clip` overwrites the
state's `motion` with the BASE value's JSON before the video group is
decoded. That restore is at the `Value` level for two reasons — `clamp_video`
is never handed the base props, and a malformed `motion` would otherwise fail
the whole group's decode and discard every other animated property — and it
is GUARDED on the group still being an object, since an end patch may have
replaced `video` with a number, a string, an array, a bool or a null and each
of those must keep falling through to the base props exactly as it always
did.

An action's end patch is **walked like every other patch** and lenient about
VALUES. `set_action_end` refuses an unknown key, a value of the wrong JSON
kind and a misspelt variant, naming the dotted path with the group's name in
it (`unknown key "video.filters[1].kindd" in an action end patch`) and the
value sent — the three groups it may name are `video`, `audio` and `text`,
and a `null` at any depth REMOVES that key rather than clearing the property,
so it is the one value the walk always lets past. What it does not do is
range-check: the state a clip interpolates toward may legitimately name a
value no stored group could hold, and a half-written animation must stay
editable, where `set_video` and its siblings are **strict** and name an
out-of-range value. Forward compatibility — a project a NEWER build wrote —
is the FILE reader's, which keeps an `end` object exactly as it found it.
The evaluator is therefore the last line of defence: `frame_recipe` and
`clip_state` clamp every value they produce to the same table the ops
enforce (opacity 0–1, scale 0.01–10, gain 0–4, non-negative radii and
crops) and collapse a NaN to that field's neutral value. The compositor
never has to defend itself, and one bad number cannot blank a frame.

### 5.5 Purity and undo

Every edit is `fn(&Project, args) -> Result<Outcome, String>`
(`core/src/outcome.rs`). An op the core UNDERSTOOD answers one of three
ways:

- **applied**, with the new project — the app pushes an undo step;
- **an identity** — the project already says what was asked, so nothing
  would change and there is no phantom undo step, and nothing to explain;
- **refused**, with the rule's own sentence — the overlap rule names the
  two clips and the exact tick counts. No undo step either: a refusal is
  not an error tier, it is an answer that can say why. It crosses the FFI
  on `rc_project_apply`'s `reason_out`, beside and never with `err_out`.

A request the core could not read is the fourth answer and the `Err` of
that `Result`: invalid arguments, unknown ids and parse failures, reported
at the FFI through `err_out`, never a panic. It is not an arm of `Outcome`
because it is about the REQUEST where a refusal is about the PROJECT.

**An identity and a refusal are identical to the person at the machine** —
both beep, neither makes an undo step — and differ only in what a caller can
be told. **Which of §6's "refuses" carry a sentence today is a list that
grows**, and `Outcome::Identity`'s own doc comment is the one place it is
kept, so a reader does not grep ten modules for it. Two families are
identities on purpose and will not join it: an op handed an **empty
selection** (fourteen ops — eight with a guard of their own, `split` and
`paste_attributes` through the same answer with none — since nothing was
asked for, so there is no rule to name), and **a clamp that landed where the
clip already was** (a slip or a roll the clamps reduce to nothing, a trim whose two
clamps crossed, a rate stretch outside ×0.1 – ×10), where "nothing needed to
change" is the honest answer as well as the true one.

The Swift document keeps a stack of handles; `NSUndoManager` records the
previous one (`ImageDocument.swift` in Rasterize is the template —
`applyEdit`, `beginLiveEdit`/`updateLiveEdit`/`endLiveEdit`,
`countEditChange`, `registerUndo` nowhere else). Because the value holds
no pixels this is cheaper than Rasterize's equivalent.

### 5.6 Persistence

`.reelcut` is a package (UTI `com.kgalligan.reelcut-project`, conforms to
`com.apple.package`), read and written through NSDocument `FileWrapper`s:

```
Talk.reelcut/
  project.json          # §5.2; RC_FORMAT_VERSION bumps on any schema change
  cache/                # regenerable; never required to open
    thumbs/<media id>/<index>.jpg
    thumbs/<media id>/complete.json    # completion marker, written LAST (below)
    peaks/<media id>.bin        # f32 max-magnitude per bucket, 100 buckets/s
    peaks/<media id>.complete.json     # its marker, a sidecar; the .bin keeps its name
    speech/<media id>.bin       # f32 Silero VAD probability per 32 ms chunk (road map 4)
    speech/<media id>.complete.json    # its marker, a sidecar carrying the model and chunk size
    reversed/<media id>-<digest>.mov   # pre-rendered reverse (M3)
  media/                # only after Consolidate (M3)
```

The reader accepts every prior version; the writer enforces the reader's
caps (4096 clips, 64 tracks, 1024 markers, 1024 media, nests 8 deep — the
`MAX_*` constants in `format.rs`, four of them mirrored as `RC_MAX_*` in
the header). Opening a project whose media is missing opens anyway with
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

**Completion markers** are what make "a cache already on disk is not
rebuilt" a true sentence rather than a hope. A filmstrip or a waveform pass
writes its marker LAST — `thumbs/<id>/complete.json` inside the strip's own
directory, `peaks/<id>.complete.json` beside the `.bin` — holding the
source file's byte size and modification second plus the media-record
fields that size the cache (duration, width, height, has video, has audio)
and the generator's own constants, so a change to any of them invalidates
every old cache. A pass begins by comparing that marker with the file the
media resolves to NOW and returns without decoding when they match; a
missing, partial (no marker: a first save mid-pass, a process that died) or
mismatched cache (Relink…, a file edited in place) is deleted and rebuilt —
the old frames and the old `.bin` go BEFORE the rebuild starts, and a
withdrawn waveform is announced at once, so nothing reads the previous
file's sound while the new one is measured — and the rebuild says so in
`.mediaCacheDidChange`, which is what lets the timeline drop the old film's
tiles it had already decoded. A pass writes its marker only for a strip it
can vouch for: at least one frame landed, and every frame it wrote is still
there when the loop ends (an in-place save while a pass runs swaps the
package under it, and a frame written between the save's listing and the
swap is lost — a strip with such a hole gets no marker and is rebuilt at the
next open, as every strip was before markers existed). The marker
carries NO path, deliberately and unlike the digest above: a reverse names a
file in a directory shared with other sources and must tell them apart,
while a marker sits inside one media's own cache with nothing to
disambiguate — and leaving the path out is what lets a moved package, a
consolidated copy and a copy on another disk keep every filmstrip. It is not
a content hash, for the reason the digest gives. Passes for one media run
one at a time and in the order they were asked for, so two sources can never
interleave under one marker; a queued pass re-reads the marker when its turn
comes and usually finds nothing to do.

**Transcription extracts are not a cache entry at all.** Generating
captions (§4.3, §7.9) writes each clip's own source window to a temporary
audio file and deletes it when the run ends: it goes to
`NSTemporaryDirectory()`, never into the package. A reverse is kept because
re-making it is minutes of work; an extract is seconds of work whose whole
product is the words, which are already in the project as clips.

`fileWrapper(ofType:)` is a whitelist of `project.json`, `cache/` and
`media/`: a directory not named there is DELETED by the next save.

## 6. Edit operations — exact semantics

All ops take clip/track/marker *ids*. All time arguments are snapped to
the frame grid first, and so are the tick values a PATCH carries — a motion
preset's two edge durations and its `during` period, and a text animation's
`in` and `out` — which the core snaps after the range checks, so a refusal
names the number the caller sent.

**How to read a "refuses" below.** An op the core understood answers one of
three ways (§5.5): it applies, it is an **identity**, or a rule **refuses**
it and hands back that rule's own sentence. The rows below name the RULE,
which is what a reader needs — a row that says an op refuses on an empty
selection or when nothing changes is naming an identity, which carries no
sentence, and every other "refuses" is a rule that either speaks already or
is a candidate to. §5.5 says where the one list of the ones that speak is
kept. Either way the project is exactly as it was and no undo step is made,
and the UI beeps or animates back; "error" = `Err`, the request itself could
not be read.

**Every op that takes a caller-authored PATCH reads it the one way** (§5.2):
a nested object MERGES key by key at every depth, a key set to `null` CLEARS
it, and an array REPLACES its whole list. The core is the one validator of
what a patch may carry — an unknown key, a value of the wrong JSON kind or a
misspelt variant at any depth is an error naming the dotted path with array
indices and the value sent, the project is untouched and no undo step is
made. The agent door forwards the caller's own object unread (§7.9), so an
agent and the app's own writers meet exactly the same rules.

**The envelope's one non-argument key: `scope?: u32`.** A nest id. Absent
(or `null` — the envelope reads the two the same way), every id in the op
resolves against the timeline, as it always did. Present, every id in the
op — clips, tracks, actions — resolves against that nest's own tracks and
clips, and the op itself is unchanged: `Project::apply` builds a **view
project** out of the nest (`tracks` / `clips` the nest's, the canvas SIZE
its frozen pair, the rate / background / switches and the `media[]` and
`next_id` the parent's, no markers, and the nest's own row kept in
`nests[]` with its contents emptied so ids resolve without being counted
twice), applies the op to it, and merges `tracks`, `clips`, `next_id`,
`media` and `nests` back. So `Project::clip` keeps its one meaning, no op
gained a nest-aware code path, undo is still one stack of parent handles,
and `rc_op_names` is still 57 — a scope is an envelope key, not an op.
Times inside a scope are the nest's own, measured from its zero; a nest has
no speed, so `t − nest_clip.start` is the whole mapping.

**Seven ops are an error with a scope**, each naming itself and the nest
(`add_marker has no meaning inside nest 4`): `add_marker`, `set_marker`,
`remove_marker` — a nest has no `markers[]`, and the timeline's are project
time and chapter points on the file; `set_canvas` — a nest's size is frozen
at the size the parent had when it was made (§5.2), deliberately, and the
rest of a canvas is the document's; and `add_media`, `relink_media`,
`remove_media` — a nest references the parent's `media[]` in the parent's
one id space, so a media edit inside a scope is a media edit on the
document wearing a scope. An unknown `scope` is `no nest with id N`,
answered ahead of everything else; a `scope` that is not a nest id is
`scope must be a nest id, not <value>`. Everything else works inside a nest
as it works on the timeline, `nest` and `unnest` included: nesting the
whole of a scope mints a fresh id and puts the new nest clip INSIDE the
scoped nest, which is a legal extra level and not a cycle.

**A scope widens §5.5's invalid-argument answer and nothing else.** Two
invariants are invisible from inside a view — the caps count the whole
document (§5.6) and the nesting depth is measured from the timeline down —
so both are checked once, at the end, on the MERGED parent. *An op may
succeed against the view and the scoped apply still return `Err`*: `too
many clips`, `too many tracks`, `nests are more than 8 deep at nest N`.
`core/src/scope.rs`'s module doc is the full contract.

**Clips**

| Op | Semantics |
|---|---|
| `add_clip {track, media, at}` | Whole media as one clip at `at`; source in 0; Fit scale if `fit_new_clips` and the source exceeds the canvas. The length is the media's, snapped DOWN to whole frames, so the window stays inside the file and the segment plays at rate 1 (§11); a timed media shorter than one canvas frame is an `Err` naming the frame. Refuses if the overlap rule fails. |
| `add_text_clip {track, at, duration=5 s, text?}` / `add_shape_clip {…, shape?}` | Same placement rules; default text is the Title preset centered, default shape the rectangle — except that `shape.kind = "arrow"` is created with `arrow_end` on, since an arrow with no head is a diagonal line. `text` and `shape` are **patch objects** in the `set_text` / `set_shape` shape, merged over that default — not a bare string or kind — so an explicit `arrow_end: false` still wins. (The MCP tools additionally accept a bare string as shorthand: the words for `text`, a kind name for `shape`.) |
| `add_background {media?, color?=white, duration?=the timeline's length}` | A backdrop on a NEW back-most track, starting at 0 and named "Background". With `media`, that file placed as `add_clip` would place it but for its SCALE — the right source kind, audio props when it has sound, and a FILL scale where `add_clip` takes a Fit one, because a plate that leaves the canvas showing down one side has failed at the one thing a background is for; with `color`, or with neither, a canvas-sized filled rectangle with no stroke at scale 1. The plate default is WHITE, not black: the canvas is already black, so a black plate is a command that appears to do nothing. `Err` for `media` and `color` together, an unknown media, a media with no pictures, a colour outside 0–1, or a duration under a frame. A full-canvas GRADIENT is this clip and a `set_shape {gradient}` after it — the canvas background stays one colour (§5.2). |
| `add_blurred_background {clip}` | The screencast backdrop: `clip` copied onto a NEW back-most track at the same start, duration, speed and source window — so the two play the same frames — scaled to FILL the canvas, centred, uncropped, blended `normal` and blurred at full strength. The copy is muted (`enabled` becomes `{video: true, audio: false}`, `detach_audio`'s pair read the other way) and drops its `audio.duck` — the one field of that group that lowers OTHER material, so a copy keeping it would duck the mix including the clip it came from — along with its transition, its actions, its label and its `video.motion` (format version 8 — a backdrop that slid in or pulsed behind the clip it copies would be two pictures of one recording disagreeing about where they are, and a slide would leave the canvas showing down one side, which is the one thing a background exists to prevent); it is named "Blurred Background". `Err` for an unknown clip, a NEST (flattening drops a nest clip's own filters, so the copy would come out sharp), a source with no pixel size (text, audio-only), or a clip with no video properties. Both of these mint TWO objects — a track and the clip on it — and the TRACK takes the `next_id` the call was made with, the clip the one after. |
| `insert_clip {track, media, at}` | The INSERT edit: the clip `at` is strictly inside on `track` is split, every unlocked track opens by the media's whole length (`insert_time`), then the media lands at `at`. Only the destination track is cut — a straddler on another track rides the shift whole, which is what keeps a bed unbroken. One op, so one undo step and one tool. Refuses when the clip could not be placed after the room was made, which is what a locked destination track gives. |
| `overwrite_clip {track, media, at}` | The OVERWRITE edit: `[at, at + media length)` is cleared on `track` ALONE — cut at both bounds, whatever is left inside removed — and the media lands there. Nothing shifts and no other track is touched; the named track is cleared whether or not it is locked, exactly as `ripple_delete` removes the clips it was given. |
| `move_clip {clips, delta, track?}` | Shifts by `delta` ticks (may be negative; clamps at 0) and optionally to another track (all selected clips keep their relative track offsets). **Overlap rule** on the destination track: a clip may overlap at most one neighbour on each side, and each overlap must be ≤ half of the shorter of the two clips; anything else refuses. An overlap is a transition; a clip that gains a predecessor overlap gets `transition_in = cross_dissolve` if it had none. |
| `trim_start {clip, to}` | New start `to`; source in advances by `(to − start) × speed`. Clamps: `to ≥ start − in/speed` (source bound), `to < end − one frame`. |
| `trim_end {clip, to}` | New end `to`; clamps to the source's remaining length (`media` sources), snapped DOWN to a whole frame so the clamp cannot put the end past the file (§11), and `> start`. |
| `rate_stretch {clip, to_end}` | `speed = source_len / (to_end − start)`; duration follows. Media sources only — a non-media clip is an **error**, not a refusal, so an MCP caller gets a message it can correct from (the UI never offers it). |
| `slip {clip, delta}` | Slides the source under a fixed clip: `in += delta × speed`, start and duration unchanged, so nothing downstream moves. `delta` is TIMELINE ticks; positive shows later material. Clamped so the window stays inside the media (`in ≥ 0`, `in + duration × speed ≤ media.duration`), and a slip the clamps reduce to nothing refuses. A `still` moves its `at` instead — it has a source time if not a window. Any other source is an **error**, as `rate_stretch` is. Actions are clip-relative and do not move. |
| `roll {clip, to}` | Moves a hard cut: this clip's start and its predecessor's end both become `to`, and nothing else moves — the pair's outer edges and its total length are invariants. The predecessor is the clip on the same track ending EXACTLY at this one's start; with a gap or an overlap there instead it refuses (an overlap is a transition, and its length is `set_transition_duration`'s). Clamped four ways: one frame kept on each side, this clip's own source head, and the predecessor's remaining source. Front-trim semantics here (`in` follows), a plain end trim there. |
| `split {clips?, at}` | Two clips. Second: `start = at`, `in += (at − start) × speed`, base props = the evaluated state at `at`. Actions before `at` stay with the first; after go to the second (start rebased); a straddling action becomes two — the first half's end patch is the evaluated state at `at`. `transition_in` stays with the first. A PRESET anchored to the clip's two ends is divided rather than copied (format version 8): the first half keeps `video.motion.in` and loses `out`, the second keeps `out` and loses `in`, each normalised to `null` when nothing is left, and `text.animation` is split the same way — `out` zeroed on the first half, `in` on the second, the pair becoming `null` when both are 0. Carrying both to both halves, which is what a clone does and what version 5 did, makes the first half leave at the cut and the second arrive again there. A `during` slot survives on both, since it is anchored to neither end, and restarts at each cut. Every splitter in the crate routes through this — `split`, `delete` and the two range cuts, `lift_range`, `insert_clip`, `overwrite_clip` and `freeze_frame` — so the rule is stated once (`edit_split.rs`, §7.10). Refuses when `at` is not strictly inside. **Omitting** `clips` — not passing a flag — means every unlocked clip `at` is strictly inside, the ⌘T-with-no-selection case. |
| `delete {clips}` | Removes; gaps stay. |
| `ripple_delete {clips}` / `ripple_delete_range {from, to}` | Removes; then for each removed span (union of the removed clips' spans, processed right-to-left) shifts every clip on **unlocked** tracks whose start ≥ span end left by the span length. Clips on other tracks that straddle a span are left in place. Range form: every unlocked clip is split at both bounds first, the middle pieces removed, then the shift. |
| `ripple_delete_ranges {ranges: [[from, to], …]}` | Several ranges as ONE edit — the silence cut. Each pair is snapped, clamped and ordered exactly as `ripple_delete_range`'s one is (a reversed pair is the same range), the pairs are then MERGED — touching as well as overlapping — and the survivors cut and closed right to left. So the op is **merge-then-cut and not N `ripple_delete_range`s**, and the difference is visible in the document: a cut at a boundary that no longer exists would mint a fragment and burn an id. `set_gained_transitions` runs once at the end, over the unlocked tracks. Markers do not move, as they do not for the singular. An empty list, and a list that merges to nothing, change nothing. Written by Clip ▸ Remove Silences… as one undo step, whatever the number of cuts. |
| `lift_range {from, to}` | `ripple_delete_range` without the close: every unlocked clip is split at both bounds and the middles removed, and NOTHING moves — every clip after the range keeps the moment it had, and so do the markers. ⌫ with a range and nothing selected, where ⌘⌫ ripples. |
| `insert_time {at, length}` | Shifts every unlocked clip whose start ≥ `at` right by `length`. Straddling clips are left in place. |
| `close_gap {track, at}` | Closes the empty span on `track` that contains `at`, bounded by the nearest clip edges there (0 in front when nothing precedes it): everything from the gap's far side shifts left by its length, across every unlocked track, straddlers staying put. Refuses on a locked `track`, on an `at` that is on a clip, when there is no clip after the gap, and when the shift would break the overlap rule — a gap closes fully or not at all, because a partial close leaves the user unable to tell whether the op ran. Markers do not move. |
| `set_speed {clip, rate, keep_pitch?}` | `duration = source_len / rate`; actions keep their clip-relative *fraction* of the clip. Media sources only, an **error** on any other kind (as `rate_stretch`). Rate is clamped to ×0.1–×10. |
| `set_reversed {clip, reversed}` | Plays the media back to front, or forward again. The core does no pixel work, so this changes neither the plan nor the recipe: Swift substitutes a pre-rendered reversed asset for that media's segments (§11). `in` is measured in the direction the clip PLAYS, so reversing keeps the in point and therefore shows different frames; the alternative would put two conventions into every trim and split. Media sources only, an **error** on any other kind. |
| `freeze_frame {clip, at, duration=2 s}` | `split` at `at`, `insert_time(at, duration)`, then a `still {media, at: source time}` clip filling the gap on the same track with the original's video props, LESS its `video.motion` (format version 8): a still is a new clip with new ends, so one taken mid-arrival would otherwise arrive again and one taken anywhere would carry a departure onto a frame that is meant to hold. The placement it keeps is the un-moved one, since evaluation never applies a preset, so a freeze taken mid-motion jumps to where the inspector said the clip was. Media sources only, an **error** on any other kind (as `rate_stretch`). |
| `detach_audio {clip}` | `enabled.audio = false` on the clip; a new clip with `enabled = {video: false, audio: true}`, same source/in/duration/speed and the audio props, on the track below (a track is inserted at index 0 if needed). Refuses if the media has no audio or audio is already detached. |
| `duplicate {clips}` | Copies placed after the originals' span on the same tracks (⌥-drag then moves them). |
| `paste {at, track?, payload}` | Inserts the clips of a clipboard payload — `{"clips": [...], "media": [...]}`, what ⌘C wrote to `com.kgalligan.reelcut.clips` — with fresh ids for the clips, their actions and any media row added. The EARLIEST clip lands exactly at `at` and the rest keep their offsets from it. A payload clip's `track` is a **depth from the front** (0 = front-most), not an id, since the ids belong to the document copied from: `track` names where depth 0 lands (default: the front-most track), the rest follow by the same index delta, and tracks missing behind it are added. Media is matched to `media[]` **by path** — reused when it is there, appended when it is not — so a paste between documents brings the entry with it. A clip the overlap rule refuses on its target track goes on a new track in front (as Add Text does, §4.1), so the only refusal is an empty clip list; a malformed payload is an **error**. |
| `paste_attributes {clips, payload, groups?}` | Copies the payload's EARLIEST clip's property groups onto each clip (at one start the front-most, then the lower id — never the array's first, which is Copy's creation order) — `payload` is the same Copy payload `paste` takes, and only that clip's `video`, `audio`, `text` and `shape` are read; its ids, times, media rows and nests do not matter and nothing is minted. A group is REPLACED whole, never merged: video and audio whole, transform included (`audio.muted` and `keep_pitch` travel — they are properties like opacity); text but its `content`; a shape but its `kind`, `width`, `height`, `from` and `to`. `groups` ∈ `video`, `audio`, `text`, `shape`: absent, it means every group BOTH sides have, silently skipping the rest; a NAMED group the payload clip lacks, or a target lacks, is an **error**, all-or-nothing, and so is a copied value the inspector would refuse — each copied group passes the patches' range checks. Speed, enabled, actions, the transition, the source and the clip's own name and label stay. Refuses when nothing changes, and on an empty `groups` list. |
| `nest {clips, name?}` | Collapses the selection into ONE clip showing a nest (§5.2), on the front-most track the selection occupied, running from the earliest start to the latest end. The clips move whole — ids, props, actions, transitions — keeping their relative times (the earliest starts at 0 inside) and their track order, onto fresh tracks of the nest's own that copy the source tracks' names and their hidden/muted/locked/solo state (a copied solo is then judged among the nest's own tracks, §5.2). The nest's canvas is frozen at the project's current size, so a later `set_canvas` cannot re-lay-out what is inside it. Media is untouched: a nest references the project's `media[]` in the same one id space. Refuses on an empty selection, on a selection of one nest clip, and when the nest clip would break the overlap rule against what was left behind. |
| `unnest {clip}` | The inverse: the nest's clips return at `clip.start + their own start` with fresh ids (as `split` then a re-join mints fresh ones), on tracks counted back from the nest clip's own — the nest's front-most track lands where the nest clip was — with tracks missing behind added, and the nest clip goes. A clip the overlap rule refuses lands on a new track in front, as `paste` does, so a group can always be opened. A nest clip trimmed shorter than its contents gives **all** of them back: there is no in point on a nest, so this is the inverse of `nest`, not of the trim. The nest is dropped from `nests[]` when no clip anywhere still shows it. An **error** when `clip` is not a nest clip. |
| `set_video {clips, patch}` / `set_audio` / `set_text` / `set_shape` | Merge the patch into the base props. Refuses if nothing changes. An unknown key, a value of the wrong JSON kind or a misspelt variant anywhere in the patch is an **error** that names the dotted path to it, array indices included, and the value sent — `unknown key "filters[1].kindd" in a video patch`, `bad value at "shadow" in a video patch: expected an object, not 5`, ``bad value at "filters[1].kind" in a video patch: unknown variant `glw`, expected one of `blur`, …`` — so a number where a shadow belongs is refused rather than read as a clear, and a list where an object belongs (or an object where a string belongs) is refused rather than read field by field; `add_text_clip`'s `text` and `add_shape_clip`'s `shape` answer in the same words. One value is refused by the CLIP rather than by the vocabulary: `video.blend` on a nest clip is an **error** naming it (format version 6), because a nest is flattened rather than composited offscreen and there is no group picture for a blend to combine with. It fires on the MERGED value only, so `{"blend": "normal"}` on a nest clip is the identity and refuses instead — otherwise an all-or-nothing `paste_attributes` of an ordinary look onto a nest clip would fail over a value that changes nothing. `set_action_end` does not range-check, so the same rule is enforced again in the evaluator (§5.4's `clamp_video`), which closes the recipe, `clip_state` and both export writers at once. A `video.filters` entry must name BOTH `kind` and `amount` — `missing key "filters[0].kind" in a video patch` — because a list replaces whole, so an entry is merged over nothing and the keys it leaves out would be completed from the type's defaults into a half-strength blur nobody asked for; the file reader keeps that completion, so an older file still opens with the defaults it always had. `video.obscure` and `shape.gradient.stops` entries are NOT held to it: their omitted keys leave the entry recognisably the thing the caller named. `video.motion` (format version 8) deep-merges like every other nested object — `{"motion": {"in": …}}` keeps a stored `out`, and `{"motion": {"in": null}}` clears that slot alone. The APP's two writers still send the WHOLE object with nil slots as `null` (the inspector's Motion section and Clip ▸ Motion ▸ know all three slots), which is the same rule spelled out rather than a second one; an AGENT's patch is the caller's own object, forwarded unread (§7.9). `{"motion": null}` clears the field, and a motion whose three slots are all null is normalised to `null` before the range checks run, so one clip has one spelling of "no motion". |
| `set_clip {clips, patch: {name?: string \| null, label?: string \| null}}` | The fifth patch op: sets or clears the clip's own name and label (§5.2). Inside the patch an absent key keeps, `null` clears, and so does an empty string — after the trim a name gets on its way in — because an unnamed clip is `null`, not `""`. Any other key is an **error**, checked before the clip ids. A patch and not two top-level arguments, because the op envelope reads an absent optional and an explicit `null` as the same thing, and "keep" and "clear" have to differ here. A `split`, `duplicate`, `detach_audio` or `paste` carries both along (they clone the clip); `paste_attributes` never does. Refuses if nothing changes. |
| `set_enabled {clip, video?, audio?}` | Visibility/mute per clip. |
| `set_transition {clip, kind\|null}` | Sets `transition_in`. With a kind on a clip that already HAS a transition only the `kind` moves — its `curve` and `audio` stay where the person put them (format version 7), because a kind chosen from the popup, the menu or MCP must not reset a curve; a clip that had none gets a minted one (§11, R5-2). `set_transition_duration {clip, duration}` moves the clip so the overlap equals `duration` (subject to the overlap rule). |
| `add_transition {clip, kind?, duration, align="center", ripple=false}` | Makes an overlap at the HARD CUT before `clip` out of the two clips' unused handles and puts a transition on it — **nothing else on the timeline moves** and the pair's outer edges stay (§11, R5-3). `align` `center` takes half from each side (the odd frame to the incoming clip, and a side that cannot supply its share passes it to the other before the total shrinks), `before` takes it all from the incoming clip's head, `after` all from the outgoing clip's tail. The duration is snapped DOWN to whole frames before the split — snapping two halves separately would lose the odd frame — and then clamped: to each side's handle (a media clip's source window; UNBOUNDED for a still, an image, text or a shape; **0 for a nest's head**, since trimming a nest clip's head moves its contents, and the nest's own remaining length for its tail), to the neighbours on the track, and to the overlap rule, which is stepped down from the larger side until it passes. A request that clamps below one frame is REFUSED, in a sentence naming the cut, the frames asked for and `ripple: true` as the way past it. The incoming clip's `in` moves back by the extension times its speed, and its ACTIONS move with it — where `trim_start` deliberately leaves actions alone, because a transition reveals material in front of a first frame nobody asked to move. `kind` absent uses the clip's own stored kind if it has one, else `cross_dissolve`; a stored transition keeps its style and a new one is minted. **Error** for a non-positive duration, an unknown clip, and for not being at a hard cut — naming which of: no predecessor, a gap, an overlap that already exists. **`ripple: true` makes the overlap by MOVING instead** (§11, R5-3's amendment): no handle is read and `align` is ignored; the incoming clip and every clip at or after the cut on every UNLOCKED track slide left by the snapped duration — `close_gap`'s set, through the same shift — so the timeline gets shorter, the outgoing clip keeps every frame and its place, and no source window or action moves. The duration is capped at half the shorter of the two clips and stepped down a frame at a time until every track something moved on passes the overlap rule; a clip on another track pushed into its neighbour gains a minted `cross_dissolve` (`close_gap`'s rule); markers do not move; an incoming clip on a locked track, or nothing left above one frame, is REFUSED, each in its own sentence. The same hard-cut `Err`s apply. |
| `set_transition_style {clip, curve?, audio?}` | Sets the transition's easing and whether it crossfades the sound; an absent key KEEPS. A separate op rather than two more arguments on `set_transition`, because that one reads an absent `kind` and an explicit `null` as the same thing and so cannot spell "keep". It stores on the same terms — any clip, with or without an overlap — and a clip with no stored transition and at least one key given gets a minted `cross_dissolve` with the style applied. NEITHER key given is an IDENTITY whatever the clip holds, and never mints — nothing was asked for, so there is nothing to explain. **Error** for an unknown clip. |

**Actions**

| Op | Semantics |
|---|---|
| `add_action {clip, at, duration=1 s}` | Refuses if it would overlap another action or run past the clip end. End patch starts empty (= no change until edited). |
| `add_zoom_action {clip, at, duration=1 s, region: {x, y, width, height} \| null, fit="fit", curve="ease_in_out"}` | An `add_action` whose end patch is the `scale`, `x` and `y` that bring `region` to the canvas — the screencast zoom. **`region`'s `x` and `y` are its CENTRE** and `width`/`height` its size, both source pixels from the centre of the cropped rect (§5.3's one region frame); the field names say neither, so the tool description and the core's doc say it too. `fit` shows the whole region, `fill` covers the whole canvas, both measured THROUGH the clip's rotation — a rectangle contains a rotated rectangle exactly when it contains its four corners, and the test collapses to the naive form at 0°. Rotation and crop — and nothing else — are read from the clip evaluated at `at`, the frame the rectangle was drawn on: the `scale`, `x` and `y` it writes are absolute, so the placement never reads a transform, base or evaluated. A rotation animated between `at` and `at + duration` is not tracked. The scale clamps to the layer maximum and the offsets are derived from the CLAMPED value, so a region too small to reach it still lands centred and only the magnification degrades. `region` absent or `null` is a zoom BACK: the end patch is the clip's STORED base `scale`, `x`, `y` — the one thing here that is NOT read evaluated, because "back" means where the clip sits when nothing is animating it, which is also what a later zoom on the same clip measures from. It composes `add_action` + `set_action` + `set_action_end`, so it is one undo step and inherits every `add_action` refusal rather than restating it; a clip with no video properties is an **error**. The region is read the way a patch is: it must BE an object (a four-number LIST is refused rather than read member by member), an unknown member and a missing member are **errors** naming the member beside the four it takes, and a wrong-typed one names its path (`bad value at "region.width"`). A non-finite or non-positive number is an **error** too — `region.width must be greater than 0` — because a zero-width region asks for an infinite scale. |
| `set_action {clip, action, start?, duration?, curve?}` | Same overlap checks. |
| `set_action_end {clip, action, patch}` | Merges into the end patch; a key set to `null` removes it, at any depth. The patch is walked like every other one (§5.4): the three groups it may name are `video`, `audio` and `text`, and an unknown key, a value of the wrong JSON kind or a misspelt variant anywhere in it is an **error** naming the dotted path with the group in it — `unknown key "video.filters[1].kindd" in an action end patch` — and a `shape` object is an unknown key, because a shape is not animatable and the key would be stored, reported as success and animate nothing. VALUES are not range-checked, so an end state may name what no stored group could hold and the evaluator clamps it (§5.4's `clamp_video`). One refusal is about the op rather than the vocabulary: a `video` object naming `motion` is an **error** (format version 8, §5.4), because a preset is anchored to the clip's two ends rather than being a value to ramp between two states, and the evaluator would restore the base value anyway. |
| `remove_action {clip, action}` | |

**Tracks, markers, canvas, media**

| Op | Semantics |
|---|---|
| `add_track {index?, name?}` | Inserts (index 0 = back). |
| `remove_track {track, with_clips=false}` | Refuses on a non-empty track unless `with_clips`. |
| `move_track {track, index}` · `set_track {track, name?, hidden?, muted?, locked?, solo?}` | Omitted fields keep their value. `solo` (format version 3) is §5.2's container rule — while any track in the set is soloed every other is treated as muted, mute wins, audio only, a nest's tracks judged among themselves — applied as a 0 envelope in `audio.rs` (§7.2) and never in the plan, so a solo toggle changes ramps and nothing else. |
| `remove_empty_tracks` | |
| `add_marker {at, name?, chapter?, color?}` · `set_marker {marker, time?, name?, chapter?, color?}` · `remove_marker {marker}` | Markers snap to frames; two markers may not share a time. Default color `red`. |
| `set_canvas {width?, height?, fps?, background?, rescale_clips?, fit_new_clips?, timecode_frames?}` | `rescale_clips` multiplies every clip's `x`, `y`, `scale` by the size ratio. Changing fps re-snaps every clip start and duration; a media clip's re-snapped duration is then held to its remaining source snapped DOWN to the new grid (§11), never shorter than one frame. |
| `add_media {descriptor}` → returns the id · `relink_media {media, path, bookmark?}` · `remove_media {media, with_clips=false}` | The descriptor is the `media[]` element minus `id`; the host probes the file. |

**This table is the SEMANTICS half of the op table, and it has a second
half.** What an op MEANS is written here and in `core/src/edit.rs`'s module
doc — including what an absent argument means, which is why the defaults are
spelled in the rows above. What an op TAKES — every argument's name, its JSON
kind and whether the decoder requires it — is DATA, in `core/src/op_table.rs`,
one row per op and one `Argument` per argument, published as one JSON Schema
per op by `rc_op_schemas` (road map 7's D3). An argument carries a range there
only where the core REFUSES outside it, sourced from the constant that
enforces it; a range the core merely clamps to is not a promise and is not
published. `OP_NAMES` is a projection of that table rather than a list beside
it, so the op count is one number in one place.

Every op is also an MCP tool with the same name, and that tool PRINTS the
arguments half rather than restating it (§7.9).

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
RcProject *rc_project_clone(const RcProject *p);
RcProject *rc_project_scoped(const RcProject *p, uint32_t nest_id, char **err_out); /* the nest as a project — §4.4, the READ half of `scope` */
void       rc_project_free(RcProject *p);
void       rc_string_free(char *s);

/* edits — one entry point. `op` is {"op": "<name>", ...args} (§6), plus the
 * optional envelope key "scope": a nest id, which applies the op INSIDE that
 * nest and returns a whole project (§4.4).
 * Returns a NEW project; NULL with NEITHER message set = an identity, the op
 * would change nothing (no undo step); NULL with reason_out set = a rule
 * refused it, in that rule's own sentence (no undo step either); NULL with
 * err_out set = invalid op or arguments (§5.5). */
RcProject *rc_project_apply(const RcProject *p, const char *op, char **err_out,
                            char **reason_out);

/* queries */
int64_t rc_project_duration(const RcProject *p);
char   *rc_project_composition_plan(const RcProject *p);              /* §7.2 */
char   *rc_project_frame_recipe(const RcProject *p, int64_t t);       /* §7.3 */
char   *rc_project_frame_recipe_opts(const RcProject *p, int64_t t, const char *opts_json); /* §7.3; {"burn_in_timecode": bool}, NULL = the defaults */
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
build the op JSON, and they live in `ReelOps.swift` — cut out of
`ReelCore.swift` under the size rule when road map 2's phase 9 came to add
`scope` to the op envelope, so the struct and the ~55 writers that set its
fields are one edit rather than two. There is no untyped call site outside
those two files — an op whose door forwards a CALLER's object (since deepening
D1: the agent's property patches, its two colour-only arguments and
`add_zoom_action`'s region) gets a RAW factory beside its typed one
in the same table, taking that object whole, rather than op JSON written
somewhere else. What an op MEANS lives in the module doc of `edit.rs`
(the `adjust.rs` "module doc is the schema" pattern) and what one TAKES is
`op_table.rs`, as data, published through `rc_op_schemas` as one JSON
Schema per op (`op_schema.rs`, road map 7's D3·2) and read back by
`ReelOp.coreSchemas()`; `ReelOps.swift` mirrors the two.

`rc_project_scoped` is the READ half of the envelope's `scope`, and it is the
one export that hands back a handle built out of a project rather than out of
JSON. An edit inside a nest goes to the PARENT's handle with the op carrying
`scope`, so undo stays a stack of parent handles; but the timeline, the canvas,
the player and every snapshot read need a project whose top level IS the nest,
and that is this. **Both halves are `Project::scoped_view`** — one function, so
what the app draws and what its edits land in cannot drift apart. Its Swift
half is `ReelProject.scoped(_:)`, held by `ProjectDocument.editedProject` and
memoised there against the parent handle it was built from, because a
`ReelProject` memoises its JSON, its snapshot and its plan per handle and a
freshly built one would re-decode at every read site. The handle is for
READING; the one legitimate write against it is a probe, whose result is
dropped.

`rc_project_frame_recipe_opts`'s Swift half is `RecipeOptions`, a value type
in `ReelCore.swift`, taken by `ReelProject.recipe(at:options:)` and
`recipeJSON(at:options:)` as a defaulted argument: `.none` calls the plain
`rc_project_frame_recipe` and every other value builds the one-key
`opts_json`, so an un-optioned recipe stays byte-identical to the shipped one
on this side of the boundary as well as inside the core. Nothing here decides
what an option MEANS — the core does — and nothing on this side may fall back
to the un-optioned export when the optioned one answers NULL, which would
turn a mis-spelled option into a silently unchanged picture.

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
  (sampled at 1/30 s across their span), ducking (every other clip's
  envelope multiplied by `level` over the ducking clip's extent with
  linear attack/release ramps) and — format version 7 — the **transition
  crossfade** already folded in, **multiplied by the same
  quantities for every nest clip the segment is inside** — turning a nest
  down turns everything in it down, and muting one silences it. Muted
  clips and muted tracks produce a 0 envelope, and so does a track
  silenced by a solo: while any track in a container's track set — the
  timeline's, or one nest's own — has `solo`, every track in that set
  without it is treated as muted, and mute wins (a track both muted and
  soloed stays silent). The rule is on the set, not on what plays: a
  soloed track holding nothing audible still silences the rest. Audio
  only, and an envelope exactly like mute — the plan's segments,
  `plays_audio` and `assign` never see it, so a solo changes ramps and
  nothing else (which the app rebuilds on, as it does a mute or a
  volume change: the ramps are part of the plan JSON §7.6 compares); a
  solo inside a nest
  is judged among that nest's tracks alone, and a timeline solo on some
  other track silences a whole nest through the nest clip's own stage, by
  the same multiply.
  **The crossfade** (format version 7) is one more factor in that product:
  an overlap whose `transition_in.audio` is true multiplies the outgoing
  clip by `cos(p·π/2)` and the incoming one by `sin(p·π/2)`, over the same
  EASED progress §7.3 hands the compositor. Constant power rather than
  equal gain because the two clips of a transition are uncorrelated
  material, where `cos² + sin² = 1` holds the level and a linear pair dips
  3 dB (§11, R5-2). It is sampled across the overlap on the action loop's
  own grid — 1/30 s, widened so one span can never contribute more than
  4096 breakpoints — because neither the sine law nor an eased progress is
  a straight line. Mute, solo, ducking, volume and the fades all keep their
  precedence, since the term multiplies rather than replacing anything, and
  a pair where only one clip has sound still fades that one. **Every STAGE
  multiplies its own term**, which is where the sound parts company with
  the picture: a clip inside an overlap inside a nest that is itself in a
  transition gets BOTH fades, where §7.3's recipe picks the clip's own
  transition and stops. That is right for sound — both fades are audible —
  and it is deliberate rather than an oversight in one of the two.
  **`mono` is not in the plan at all** and never was:
  `AVMutableAudioMixInputParameters` applies gain over time and cannot
  combine channels, so the flag this paragraph used to promise ("a
  per-segment flag Swift applies with `AVMutableAudioMixInputParameters`
  where possible") described something the API cannot do — and nothing
  applied it, from M2 until road map 2's phase 5. It is sample work, so it
  travels the way pan, the compressor and noise reduction do (§4.3): per
  clip, beside the plan, into the processing tap, where it is the head of
  the Mix stage. A project that saved `mono: true` before phase 5 does now
  sound different, which is the feature.
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
      "blend": "normal", "corner_radius": 0, "shadow": null,
      "color": { "brightness": 0, "contrast": 0, "saturation": 0, "hue": 0 },
      "chroma": null,
      "filters": [], "reflection": null, "spotlight": null, "obscure": [],
      "clip_rect": null,
      "transition": null },
    { "clip": 23,
      "source": { "kind": "text", "hash": "9f3c…", "text": { …resolved text props… },
                  "reveal": 0.4, "reveal_phase": "in", "reveal_kind": "typewriter" },
      "source_size": null,
      "x": -560, "y": -380, "scale": 1.0, "rotation": 0, "opacity": 0.72, … },
    { "clip": 31, "source": { "kind": "track", "track_id": 2 }, …,
      "transition": { "kind": "push_left", "progress": 0.4, "role": "in", "partner": 17 } }
  ]
}
```

- Layers are back-to-front. Every property is already evaluated through
  actions — **and, for the five PLACED ones, moved by `video.motion`**
  (format version 8): a layer's `x`, `y`, `scale`, `rotation` and `opacity`
  carry whatever the clip's preset asks for at this instant, and there is no
  `motion` key here at all, because a preset is a statement about placement
  and this is the placement. §5.3 says what the arithmetic is and §5.4 says
  why nothing that EDITS sees it. `source.kind` ∈ `track` (a composition video track id),
  `image` (`media` id — Swift decodes with ImageIO and caches the
  texture), `text` / `shape` (the resolved description plus a stable
  content hash Swift caches textures by), `missing` (draw a slate).
- A text layer's source object carries THREE more keys (format version 5),
  and all three are present on every text layer whether it animates or not,
  because an absent key would mean two things — no animation here, or an
  older core that never computed one. `reveal` is 0 (nothing showing)
  through 1 (all of it), and is 1.0 with no animation; `reveal_phase` is
  `"in"` while the arrival is what holds the reveal back, `"out"` once the
  departure is — with the one exception the next bullet is about — and
  `null` with no animation; `reveal_kind` is
  `text.animation`'s own `kind`, spelled as the schema spells it, or
  `null`. Together they are the WHOLE of what a renderer is told about the
  animation — which routine, how far, and which way — and the recipe
  STRIPS `animation` out of the `text` description beside them so there
  cannot be a second answer: nothing downstream has the clip time to
  evaluate one against. **The CORE computes them**, from the animation and
  the clip's own time, which is what makes the preview, `render_frame` and
  both export writers agree by construction: they read one recipe. The
  layer's `hash` covers all three, so a half-revealed frame can never be
  served the whole text's cached texture — and a layer with NO animation
  hashes exactly what it hashed before version 5, so no shipped project's
  texture cache behaves differently.
- **`reveal_phase` is the ORDER the renderer draws in, not a label on the
  amount**, and where those two readings part the order wins. `word_fade`
  and `line_rise` stagger their words and lines from the OTHER end while a
  layer is leaving, so that the first word in is the first word out; the
  frame on which the phase turns is therefore a frame on which the picture
  mirrors end for end, and the one amount at which that mirror is invisible
  is 1, where every item is whole whichever end the count started from. An
  animation that FITS its clip (`in + out <= duration`) reaches 1: its two
  ramps have a plateau between them and the phase turns on it, a tie going
  to the arrival, so the mirroring never shows. A TENT — `in + out >
  duration`, which §5.2 lets degrade rather than refuse — has no plateau:
  its ramps cross BELOW 1, and turning there would swap a four-word cue's
  alphas from `[1, 1, .83, .33]` to `[.33, .83, 1, 1]` between two
  consecutive frames whose reveal did not change. So a tent keeps the phase
  it began in for the whole of its life. That is the arrival's, unless `in`
  is 0, which makes the clip nothing but a departure and leaves the stagger
  no arrival order to contradict. The limit that falls out of it is worth
  knowing before it is read as a bug: a tent whose `in` is tiny but not
  zero reports `"in"` from its first frame to its last, while the departure
  is what is actually holding the amount down.
- `blend` (format version 6) is the layer's `video.blend`, spelled as the
  schema spells it — and it is the one property here the recipe may
  OVERRIDE rather than merely evaluate. **A layer whose `transition` is
  non-null is emitted as `"normal"` whatever the clip says**, and the CORE
  decides that, not the renderer. The reason is the transition weight in
  §7.5's fragment stage (step 8 of `Compositor.metal`'s order of
  operations): the
  outgoing half of a dissolve divides its weight by the attenuation the
  incoming pass is about to apply, which is the exact algebraic inverse of
  a FIXED-FUNCTION destination factor, so a programmable blend on either
  half invalidates it — and `add_clip` onto an overlap gives the new clip
  a `cross_dissolve` by default, so that wrong picture is a minute away
  from anyone trying the feature. It is decided here for `reveal`'s
  reason, read again: everything that draws a frame reads this one
  description, so preview, `render_frame` and both export writers cannot
  disagree about it, and a core test can read the layer's `blend` at a
  tick inside the overlap where a renderer-side rule would need two PNGs.
  The consequence is worth saying out loud, because from either side alone
  it reads as a bug: **the recipe's `blend` is what DRAWS, while the
  inspector reads the MODEL's value through `clip_state`**, so during an
  overlap the popup says `multiply` and the frame composites `normal`.
  Both are honest — the clip multiplies, and this frame does not.

- `source_size` is the media pixel size, or `null` for text (the renderer
  knows) and the box size for shapes.
- `filters`, `reflection` and `spotlight` (M3) and `obscure` (format
  version 4) are the §5.2 property groups already evaluated: an ordered
  list of `{ "kind", "amount" }` at most `MAX_FILTERS` long, the two
  objects or `null`, and a list of at most `MAX_OBSCURE` regions. All four
  are always present — `obscure` is `[]` on a layer with no regions — so a
  renderer never has to ask whether the key exists. None of them is
  touched when a nest's transform is folded into a layer (§5.3): they are
  in source pixels or are per-pixel maths, and only the placement folds.
- `clip_rect` (M3) is `null`, or `{ "x", "y", "w", "h", "rotation" }` — the
  rotated rectangle in CANVAS pixels the layer is clipped to, with `x`/`y`
  the rectangle's CENTRE measured from the canvas's top-left corner and
  `rotation` in degrees clockwise. That frame is not the canvas-centre one
  a layer's own `x`/`y` use; it is the canvas's own top-left frame. It used
  to say here that this is "the space the fragment stage's position already
  arrives in" — that was true only while every render target was the canvas
  size, and road map 2's phase 8a (Preview Quality) made it false and cost
  the phase a blocker: a fragment arrives in DESTINATION pixels, so a
  canvas-pixel rectangle tested against a halved coordinate is magnified
  about the origin. The renderer now carries the ratio and converts
  (§7.5). Only a nested layer
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
  draws them as one pair. **`progress` is EASED by the transition's own
  `curve`** (format version 7) before it leaves the core, so every consumer
  of it — the shader, the dissolve's weight correction, the zoom's partner
  box — gets one number and none of them knows the curve exists. `linear`
  is the identity, which is what makes a project written before version 7
  render exactly what it rendered.
- The recipe is a few KB; parsing it per frame costs tens of microseconds.
  A binary form is a later optimization, not a design change.

**Recipe options** (road map 2, phase 7). `rc_project_frame_recipe_opts`
takes what a caller wanted BESIDES `t`, as `{"burn_in_timecode": bool}`, and
`rc_project_frame_recipe` is the same implementation with the defaults, so
an un-optioned recipe is byte for byte the one this section has always
described. Nothing here is persisted: these are a question asked of a
project, not a property of one, so no format version moves when an option is
added. An option is deliberately NOT an `rc_export_settings` override —
§7.8's override table IGNORES an unknown key so a newer UI still gets an
export, so an option sent that way would vanish silently and the export
would report success on a file it had not changed. An option that changes
the PICTURE travels with the description of the picture.

- **`burn_in_timecode`** appends ONE text layer — appended, so last, so
  topmost — to the layer list at every `t`. Its `content` is the project
  timecode at `t` through the one formatter, honouring the document's own
  `canvas.timecode_frames`, because a burn-in and the toolbar spelling one
  instant two ways is exactly what that formatter exists to prevent. It is a
  text layer like any other: all twenty layer keys, all six source keys,
  `reveal` 1.0 with a null phase and kind, a monospaced face
  (`IBMPlexMono-Regular`), a backdrop, no wrapping width and no animation.
  Its `clip` is 0, since it came from no clip.
- **Its placement is a FRACTION of the canvas height with `valign: middle`,
  not "bottom-centre"**, and reading that gap as a bug is the mistake this
  bullet exists to prevent: a layer's `y` is the offset of the text box's
  CENTRE (above), and by the standing rule of §5.3 and §11 the core has no
  measured text size to subtract from a bottom edge. It is placed the way
  the Caption preset places every caption, at a fraction of the height below
  the centre, and the box stays symmetric about the point the core can name.
- Two readings that are not bugs. The timecode is **non-drop**, like every
  timecode this library formats, so a 29.97 fps burn-in reads about 3.6
  seconds behind wall clock at one hour — that drift is the definition, and
  the toolbar has shown it since M1; a burn-in that disagreed with the
  toolbar would be worse. And it shows **project time, not file time**: an
  in/out range export rebases its samples by subtracting the range start
  while the composition time stays project time, so a range export starting
  at 00:00:10:00 writes a file beginning at 00:00 whose first frame reads
  00:00:10:00 — which is what a review copy should say, since the number
  exists to name a moment back on the timeline.

**How an option reaches a frame on the Swift side**, which is two paths and
not one. `RecipeSource` — the process-wide registry the compositor reads,
§7.6 — stores options per KEY beside the project, so `Compositor.serve` asks
for a recipe and gets the one its instruction's key asked for, and nothing in
the instruction, in `CompositionBuilder` or in `ExporterWriter.swift` carries a
flag of its own. `Exporter.export` publishes them on the fresh key it mints for
the write, which is what every frame `ExportWriter` reads back is composed
against. **But `Exporter.renderFrame` takes them as a PARAMETER as well, and
that is load-bearing rather than belt-and-braces**: it registers a key of its
own, and GIF and APNG never go through `ExportWriter` at all — the ImageIO
pipeline calls it once per frame — so an option travelling only on the
export's key would leave every image-sequence export silently unchanged. The
option is stored beside the project rather than folded into it because a
document publishes a NEW handle after every edit while the ask stays the same;
an absent entry is the defaults, so every key that never asks answers what it
answered before options existed. **Who asks:** the export sheet, the `export`
tool and `render_frame` (the last both for agent parity and because a script
can photograph a burn-in no other way); the canvas eyedropper and Save Frame
pass nothing, because each wants the picture rather than a deliverable.

### 7.4 Swift file map

| File | Owns |
|---|---|
| `ReelCore.swift` · `ReelOps.swift` · `ReelEdit.swift` · `ReelOpSchema.swift` | the core's edge. `ReelCore.swift` is the **only** `rc_*` caller: `ReelProject` (handle + lazy `ProjectSnapshot`), `RecipeSource`, the typed patches, and the op table read BACK — `ReelOp.coreNames()` over `rc_op_names` and `ReelOp.coreSchemas()` over `rc_op_schemas`, which `AgentCatalog.opTool` prints (§7.9). `ReelOps.swift` is the typed op builders, cut out of it under the size rule — one factory per row of the op table, plus the eleven RAW factories that forward a caller's own object; `ReelEdit.swift` is the three arms an edit answers (§5.5) and `ReelOpSchema.swift` the value `coreSchemas()` answers, both their own files because neither names an `rc_*` symbol |
| `MotionProps.swift` | `video.motion`'s Swift vocabulary (format version 8): `EdgeMotion` and `DuringMotion` with their display names, `MotionEdge`, `MotionDuring` and `MotionProps`, all decoded leniently and all with the core's own defaults mirrored rather than derived. Its `dictionary`s live here rather than beside every other property type's in `ReelCore.swift`, which is far over the ~600-line cap — and `MotionProps.dictionary` ALWAYS writes three keys, `NSNull` for a nil slot, because a core patch deep-merges a motion (§6) and a slot left out would leave the old one in place. Since D1·3 it is the ONLY writer of a whole motion: an agent's patch is the caller's object, forwarded unread, and merges slot by slot |
| `ProjectDocument.swift` | NSDocument, `.reelcut` package read/write, the single mutation point (`applyEdit`, live-edit trio), undo as a handle stack, dirty counting, and the FIVE pieces of view state (playhead, selection, in/out range, `selectedMedia`, `nestPath`). `nestPath` is §4.4's nest scope as the PATH it was entered by — one step per level, each naming the nest and the nest CLIP that showed it, because a nest can be shown by two clips at two different starts. `scope` is its last step's nest and is what every op is stamped with (`ReelOp.scoped(_:)`), except the seven the core refuses inside a nest, which are sent unscoped; `editedProject` is the memoised `rc_project_scoped` handle every view of the TIMELINE draws from, where `project` stays the document for save, export, captions, consolidate and the Document and Media tabs |
| `EditorViewController+NestScope.swift` · `TimelineView+NestScope.swift` | going inside a nest and coming back out (§4.4): Open / Close Nest, the double-click, the playhead mapping, and the breadcrumb the ruler draws in the corner over the track headers — one stored property, one closure, one draw call, one hit token and one gesture case in the frozen `TimelineView.swift`, `TimelineView+Candidates.swift`'s split exactly |
| `Playback.swift` · `EditorViewController+PreviewQuality.swift` · `PreviewWindowController.swift` | `AVPlayer` + `AVPlayerItem` over the plan; the rebuild-vs-refresh decision (§7.6); coalesced exact seeks; JKL rates; loop range; `preferredMaximumResolution` = canvas size. **Preview Quality** (View ▸ Preview Quality ▸ Full / Half / Quarter) scales the PLAYER's render size on a `mutableCopy()` of the built video composition, so `CompositionBuilder.build` is untouched and the export and `render_frame` paths are UNREACHABLE from the setting rather than merely unchanged by it; the size always carries the canvas's EXACT aspect (`m · (w/g, h/g)`, `g = gcd(w,h)`, `m = ceil(g/divisor)`), falling back to the next coarser exact size and finally to Full for a coprime canvas, because the overlay maps every drag handle through `AVPlayerLayer.videoRect`. **Preview Window** (⇧⌘P) is a second `AVPlayerLayer` on the SAME player in an `NSPanel` — a panel because a titled window becomes MAIN and every ⌘-item whose action is on `EditorViewController` then resolves to nothing |
| `CompositionBuilder.swift` | plan JSON → `AVMutableComposition` + `AVMutableAudioMix` + `AVMutableVideoComposition` (+ `CompositionInstruction`). Since road map 3, `fill` HOLDS a video track's last frame over any part of a segment's source range the track does not cover (§7.2): a screen recording's video track ends at the last screen change while its sound runs on, and AVFoundation inserts the uncovered range without clamping and renders it black |
| `Compositor.swift` | the `AVVideoCompositing` class and its Metal pipeline (§7.5) |
| `LayerRenderers.swift` · `LayerRenderersText.swift` | text (Core Text) and shape (Core Graphics) descriptions → premultiplied BGRA `MTLTexture`s, LRU-cached by hash; reports measured text sizes to the overlay; draws a shape's `gradient` (format version 6) by CLIPPING to the path and running `CGGradient`, sorting the stops the core deliberately does not police (§5.2). The TEXT half — the layout caches, the attributed string and the three §5.2 reveals drawn over the recipe's `reveal`, so a reveal can never reflow the box — went out to `LayerRenderersText.swift` under the size rule when phase 6 came to add the gradient |
| `CaptionImporter.swift` · `CaptionLayout.swift` · `Transcriber.swift` · `CaptionExporter.swift` | captions in both directions: the SubRip grammar; the placement every producer shares (the frame grid, the overlap trim, the Caption preset, the new front-most track); on-device speech recognition and the cue builder over it; and the `.srt` / `.vtt` writer |
| `MediaImporter.swift` | `AVURLAsset` probing (the **one** place `async`/`await` is allowed — AVFoundation's loading API is async-only going forward), thumbnails via `AVAssetImageGenerator` — the seconds at or past the video track's end ask for its last frame once and hold it, the strip's half of the rule `CompositionBuilder` applies to the picture — peaks via `AVAssetReader` + vDSP, cache files in the package |
| `Exporter.swift` | picks the pipeline for the core's settings — `ExportWriter` (`AVAssetReader`/`AVAssetWriter`: chapters, explicit bitrates, the loudness gain) or the ImageIO frame sequence for GIF/APNG — runs the loudness MEASUREMENT pass ahead of the write, reports progress, and renders one frame offline for `render_frame` |
| `ExporterSettings.swift` | the resolved settings in AVFoundation's vocabulary — the time range, the fallback session preset, the file type, the UTI, the extension, `isAudioOnly` — cut out of `Exporter.swift` under the size rule when phase 7 gave `export` and `renderFrame` a `RecipeOptions` argument; `renderFrame` stayed behind because it is the app's only `copyCGImage` call and the build baseline names that warning by file |
| `FrameWriter.swift` | a CGImage and a format in, a written file out (PNG / JPEG / HEIC) — the ONE writer File ▸ Save Frame… and `render_frame` both call, which is what makes their PNGs byte-identical by construction rather than by luck; PNG passes NIL destination properties, and JPEG flattens a transparent canvas onto black because the container has no alpha |
| `AudioTap.swift` · `AudioDSP.swift` · `LevelMeter.swift` · `LevelMeterView.swift` | the sample-level audio the plan cannot carry: one `MTAudioProcessingTap` per composition audio track running noise reduction, the compressor and the Mix stage (the mono fold, then the pan), and the level meter's model and its one view — the model publishing a raw per-channel peak and RMS lock-free off the render thread, the view owning the ballistics |
| `MediaPane.swift` · `MediaRowView.swift` · `MediaListFilter.swift` · `MediaPaneCommands.swift` · `MediaUsage.swift` · `MediaReveal.swift` | the Media tab (§4.3): the pane and its find band, the row and the drag it sources, the filter as a VALUE (search, order, unused-only), the seven commands a row calls back into, the ONE answer to "is this file used" — which walks the nests the way the core's `every_clip()` does, and which Remove and `remove_media` ask too — and the reveal, which selects and then scrolls |
| `MediaPeaks.swift` · `AudioNormalize.swift` · `SilenceDetector.swift` · `SilenceDetector+Walls.swift` | the waveform cache and the two questions asked of it: `MediaPeaks` is the one mapping from a plan segment's source window to peak buckets (the reversed mirror included, and `window`/`bucketIndex(_:bucket:)` generalised over the bucket size for `MediaSpeech` since road map 4), `AudioNormalize` turns a clip's peak into a `set_audio` op (Normalize, `normalize_clip`) and `SilenceDetector` turns peak × envelope, or since road map 4 the cached Silero VAD probability, into the quiet spans — `Mode` (`voice` / `level`), the gain floor and the per-voice level fallback (a media is named when any of its scoped segments fell back). `SilenceDetector+Walls.swift` is the nest walls, the OVERLAP walls (road map 5's E1 — one per transition on every unlocked track, widened by the overlap's own length each side and subtracted like a nest wall but never reported) and the frame-grid snap, a pure move out at road map 4's toll 1 |
| `SileroVAD.swift` · `MediaSpeech.swift` · `MediaImporter+Speech.swift` | road map 4's voice model: `SileroVAD` is the streaming Core ML wrapper over `app/Resources/Models/silero_vad.mlmodelc` — the process-wide `isAvailable`/`markUnavailable` pair, `NSLock`-guarded — `MediaSpeech` is the chunk grid (`chunkTicks`, `chunkCount`) and the cache `Loader`/`speechMax` over `MediaPeaks.window`, and `MediaImporter+Speech.swift` is the await-free head check and the reader/inference pass `MediaImporter.swift`'s `speech(for:url:stamp:into:)` calls — run AFTER `peaks` in `generateCaches`'s order, so the peaks `.bin`'s withdrawal is never held behind a full-file decode and an inference |
| `Loudness.swift` | BS.1770-4 integrated loudness and true peak over plain float buffers — no AVFoundation, no player, no tap — plus the export gain that follows from a measurement and the 16-bit scaler that applies it |
| `TimelineView.swift` | custom `NSView` in an `NSScrollView`; drawing from the snapshot; gesture sessions (`ClipDragSession`, `TrimSession`, `RangeSession`, `MarkerDragSession`) as structs; `on*` closures to the VC |
| `PreviewCanvasView.swift` | `AVPlayerLayer` under a transparent overlay `NSView`; `CanvasSession` structs for move/scale/rotate/crop; handle drawing |
| `InspectorViewController.swift` + `VideoPane` / `AudioPane` / `TextPane` / `ShapePane` / `MediaPane` / `DocumentPane` | one file per tab, descriptor-driven controls from `OptionControls.swift`. `VideoPane+Transition.swift` is the Transition section, an extension file since road map 5's E1 toll — the one group that is not about the layer's own pixels but about how it MEETS the clip before it, and the two rows E1 added (Curve, Crossfade Audio) send BOTH keys whenever the clip has no stored transition, so the minted one is exactly what the section showed |
| `EditorViewController.swift` + `EditorViewController+<Feature>.swift` | wiring only in the base file; features in extensions (Rasterize's frozen-file rule) |
| `ExportQueueController.swift` · `ExportQueueWindowController.swift` | the export queue (Window ▸ Export Queue): the job list and its state machine — one job at a time, on the main thread, a fresh `Exporter` each, every job holding the project handle and the media URLs as they were when it was confirmed — and a window that only reads it. The controller has no AppKit in it, so a probe compiled from `app/Sources` can run two jobs without a window; the queue edits no project, so it gets no MCP tool and `export` is already its mirror |
| `AppDelegate.swift` · `EditorWindowController.swift` · `WelcomeWindowController.swift` · `main.swift` | menus (nil-target selectors), window, welcome |
| `RecordingSetup.swift` · `RecordingResult.swift` · `ScreenRecorder.swift` · `+Pause.swift` · `+Delegates.swift` · `+Microphone.swift` · `+Finishing.swift` · `+Content.swift` | screen recording's session (road map 3): the values a probe can call — `RecordingChoice`, `RecordingFiles` (the folder, the Screenshot app's date stem, ` (2)` on collision), `RecordingConfiguration.make` (pure, every field read back), `RecordingGrant` (the two synchronous grant reads and the refusal sentences; nothing here prompts), and in `RecordingResult.swift` what a recording ENDS as — `RecordingResult` over `RecordingSegment`s, `StopReason`, `RecorderError` — and the machine `idle → arming → recording ⇄ paused → finishing → idle` over one `SCStream` and one `SCRecordingOutput` PER SEGMENT (a pause removes it and its file closes; a resume adds a fresh one to a file named by its own start time while the stream keeps capturing — R0 q7) for the picture and system sound and, for a microphone, an `AVCaptureSession` + `AVCaptureAudioFileOutput` writing a SECOND file per segment (§11). Every framework callback is stamped where it arrives and hopped to main, and finds ITS segment by the output's identity or the microphone file's URL; every state transition runs there |
| `RecordingLanding.swift` · `RecordingLanding+Placing.swift` · `RecordingLanding+Microphone.swift` · `ProjectDocument+Recording.swift` | where a finished recording goes: a value type answering an UNSCOPED op list and the ids the core will mint — every segment's picture back to back on ONE track by the two-try rule over the SEQUENCE (all on the front track or all on a new one), each at the previous clip's END as the core reports it, touching or a sub-frame gap at an inexact rate and never an overlap; each segment's microphone on one new back track named Microphone at ITS picture's start minus ITS offset, floored at the previous voice's end and at 0, a start below the floor head-trimmed rather than placed late, a voice wholly under the previous one or a file under a frame left as media with a note naming it — that the panel commits through `performGroupedEdit` and the tool through `AgentServer.performGroupedEdit`; and `untitled(around:)`, whose ORDER is a contract — open untitled, `adoptImported` (the one spelling File ▸ Open uses, now in the base file) with the FIRST segment, the import count, the REMAINDER's one edit (`remainderPlacement`: segments 2…n after clip 1, then every voice; named Add Microphone for one segment with a voice, else Add Recording Segments), `makeWindowControllers`, `showWindows` |
| `RecorderPanelController.swift` · `+Rows.swift` · `+Recording.swift` · `+Pause.swift` · `+Landing.swift` · `+Picker.swift` · `RecorderStatusItem.swift` · `AppDelegate+Recording.swift` · `AgentServer+Recording.swift` · `+RecordingArguments.swift` · `+RecordingResult.swift` | File ▸ New Recording… (⌥⌘N): the app's second `NSPanel` — `.floating` and `.nonactivatingPanel` so Record and the countdown's Cancel can be clicked without bringing Reelcut forward over the thing ABOUT to be recorded; the panel is off screen for the recording itself (§11) and ONE instance because it outlives documents — its first `NSStatusItem`, the recording's whole chrome: a coral dot and the elapsed time with Pause Recording · Stop Recording, the pause glyph and the FROZEN time with Resume Recording · Stop Recording; the grants asked BEFORE the countdown; and `record_screen`, the tool that never asks and whose result carries `pauses` and `segments` |
| `AgentServer.swift` · `AgentServer+<Feature>.swift` · `AgentCatalog.swift` (+`Declarations`) | MCP mirrors of every op, plus `open_project`, `import_media`, `render_frame`. `AgentCatalog+Declarations.swift` is where a tool says it takes more or less than its op does, one row and one reason each (§7.9). One handler file per feature area, the frozen `AgentServer.swift` keeping only the registry rows. `AgentServer+Transitions.swift` and `AgentCatalog+Transitions.swift` are road map 5 E1's pair (`add_transition`, `set_transition_style`); the catalog rows are spliced in beside the clip group and never appended at the end, where `recording_probe.py` reads the last eleven names |
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
- **One pass per layer, and FIVE pipelines from three fragment
  functions.** The vertex stage places a quad from a per-layer uniform
  block (canvas size, center, source size, scale, rotation, crop window as
  UV bounds); the fragment stage samples with the crop window and runs the
  order of operations written out at the head of `Compositor.metal` —
  the corner-radius mask (a rounded-rect SDF in source pixels),
  brightness/contrast/saturation/hue, chroma key (M3), the filters, the
  hidden regions (format version 4), the spotlight, coverage, the
  transition weight and opacity — and outputs premultiplied BGRA. Text and
  shape textures are already premultiplied and take the same path. Missing
  media draws a slate.
  Two independent specializations of that stage give four layer states,
  and the shadow's quad is the fifth. **`kGatherFilters`** is a function
  constant: a layer that needs a neighbourhood filter (blur, sharpen) or a
  blurred hidden region compiles the gather loops in, and every other
  layer has them compiled OUT rather than branched around.
  **`reelcut_layer_blend_fragment`** is the second entry point, added at
  format version 6: it reads the destination through `float4 dst
  [[color(0)]]` — programmable blending, which needs no ping-pong target
  on Apple Silicon — and computes `video.blend`'s combination itself,
  where the plain entry point returns its colour and lets the
  fixed-function stage apply source-over. Both share one `static inline`
  helper carrying the whole stage, because Metal cannot call one
  `fragment` function from another; a `normal` layer's pixels therefore do
  not depend on which of the two drew it, since the general formula
  reduces algebraically to the fixed-function factors.
  **The two blend pipelines are built with fixed-function blending
  DISABLED, and that is a correctness requirement nothing in the toolchain
  enforces.** Metal builds a programmable-blend pipeline with blending
  still on — no error, no validation warning — and the double blend is
  invisible over an OPAQUE destination, because the fragment stage returns
  the finished composite, whose alpha is `as + ab·(1 - as)` = 1 over any
  opaque backdrop, and `oneMinusSourceAlpha` is then 0 whatever the layer's
  own opacity is. **What decides it is the DESTINATION's alpha, not the
  layer's**, and phase 6 got that backwards first: the partial-opacity
  check written for the job passed against a build with the guard deleted,
  as did every other fixture in the script, all of which put an opaque card
  underneath. It takes a destination alpha below one AND a source that does
  not cover it — `tools/proof/phase6_proof.py`'s section 6b, the one check
  in that script that reads the ALPHA channel, where the mutant lands 32/255
  high while the colour moves by two.
- **This compositor blends in the ENCODED sRGB space, deliberately.**
  Nothing in the pipeline uses an `_srgb` pixel format — the attachment is
  `.bgra8Unorm` — so every stage works on stored 8-bit values, and so does
  the blend. "Multiply of 50 % grey over 50 % grey is 25 %" is a statement
  about ENCODED values and is FALSE in linear light, where the answer is
  about **61**/255 — three steps below the 64 the encoded multiply gives
  (60.95 against 64.25 unrounded), and three times the ±1/255 the proof's
  blend checks allow themselves, so the two readings cannot both pass. The
  number is part of the sentence: a reader who checks it and finds it wrong
  stops believing the paragraph it is in. A reader who knows colour will
  want to wrap the blend in a linearise/encode pair: that would change
  every blended pixel, break the
  measured 64 / 192 / 255 the proof asserts, and make the compositor
  disagree with itself, since the grade, the filters and the transitions
  have all worked in encoded space since M1. If linear light is ever
  wanted it is a decision for the WHOLE pipeline, not for one stage. The
  same sentence stands in `Compositor.metal`'s order-of-operations comment
  and in `tools/proof/phase6_proof.py`'s docstring, because it is the one
  thing about this compositor a competent reader will try to "fix".
- **Transitions** are one pass over the pair: dissolve = both with
  progress-weighted opacity; fade black/white = out fades to the color
  then in fades from it; push/slide = offset by progress; wipe = a UV
  threshold; zoom = scale ramp. The FOUR wipe directions (format version 7)
  are one shader branch and four vectors, as the four pushes are: the
  branch takes `local.y` when `|dirY| > |dirX|` and flips on a negative
  component, and the edge is measured in each layer's OWN box — so a
  different-size pair does not meet at one edge, which is the price of
  every nested wipe working and the common same-size pair being exact. The
  `progress` the pass reads is already eased (§7.3); nothing here knows
  about `curve`. A layer mid-transition always draws
  `normal`, and the core is what says so (§7.3), so this shader has no
  special case for it and none may be added. Shadows (M3) render the
  layer's alpha to a small offscreen texture, blur with
  `MPSImageGaussianBlur`, draw first — and the MASK pass takes the layer's
  gather specialization WITHOUT its blend, because the mask asks about the
  layer's SHAPE, which no blend mode changes. That separation is DEFENSIVE
  and not load-bearing, and phase 6's mutation run is what settled it: the
  natural fear — a `multiply` evaluated over a destination cleared to
  transparent black is 0 everywhere, so a blended layer's shadow silently
  vanishes while the layer itself looks right — is true of a naive
  `src · dst` and FALSE of the premultiplied composite this shader runs,
  whose `(1 - ab)·src` term carries the source through an empty destination:
  at `ab` = 0 the formula reduces to `src` exactly, for all eight modes. A
  build that passes the blend variant here renders every shadow correctly.
  Keep the separation — it costs nothing, it says what the mask pass means,
  and a future formula without that term would make the hazard real — but
  do not restate it as a bug it is holding back. The shadow's own draw stays
  fixed-function source-over whatever the layer's mode (a shadow is light
  falling on the backdrop, not the layer's ink), while the REFLECTION
  inherits the blend, since it is part of the layer.
- Budget: a 1080p frame in under 8 ms. Textures for image/text/shape
  layers are LRU-cached (64 entries).

### 7.6 Playback update rules

After every edit, `ProjectDocument` posts a change notification with the
new `ReelProject` and `isLive`. `Playback` then:

1. Sets `RecipeSource.current = newProject` (an atomic reference the
   compositor reads on every request).
2. Computes the plan JSON; if it equals the current plan, the edit was
   **property-only**: no rebuild — if paused, force one composed frame.
   The standard trick for that, a zero-tolerance seek to the time the
   player is already at, is a NO-OP on macOS 26.5.1 (measured by
   `tools/proof/preview_refresh_probe.py`: the completion fires and no
   composition request is issued; re-assigning the item's
   `videoComposition` is the same no-op), so `Playback.refreshPausedFrame`
   seeks one tick off the playhead — inside the same frame — and queues the
   return, landing back on the playhead's own tick with the new recipe
   drawn. Parked at the end, where the end tick composes the empty canvas,
   it rests on the last frame's final tick instead. A refresh asked for
   while a seek is in flight is run when the seek lands, never dropped.
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
redraws as they land — and both are SKIPPED when the cache's completion
marker matches the file (§5.6); a relinked, changed, partial or unmarked
cache is rebuilt. Image files (PNG/JPEG/HEIC) are probed with ImageIO
and become `kind: image` media.

Formats AVFoundation opens on macOS 15: MOV, MP4, M4V, M4A, MP3, AAC, WAV,
AIFF, CAF; H.264, HEVC, ProRes, MJPEG; PNG/JPEG/HEIC/TIFF images. MKV,
WebM, AVI and VP9/AV1 are not opened (§11).

### 7.8 Export

Presets (`rc_export_presets`), in menu order, are ENCODINGS — a container
and a codec, with no size of their own: `h264` H.264 (MP4), `hevc` HEVC
(MP4), `prores_422` ProRes 422 (MOV), `prores_4444` ProRes 4444 (MOV),
`audio_m4a` Audio only (M4A),
`audio_wav` Audio only (WAV), `audio_aiff` Audio only (AIFF), `gif`
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
whole or in/out, `optimize_for_network`, the two bitrates below and the two
loudness figures below them) to
concrete settings, no size override meaning the preset's cap where it has
one and the canvas otherwise. Each preset AVFoundation can write still
carries an `AVAssetExportSession` preset name
(`AVAssetExportPresetHighestQuality`, `…HEVCHighestQuality`,
`…AppleProRes422LPCM`, `…AppleProRes4444LPCM`, `…AppleM4A`) — that
mapping is what names the
codec and tier, and `avf_preset: null` is how a preset says AVFoundation
cannot write it at all. Since phase 5 the field means **only** that: the
name is a record, not an instruction, because `null` is what routes an
export to the ImageIO writer and AVFoundation has no `AVAssetExportPreset`
for LPCM, so `audio_wav` and `audio_aiff` repeat `audio_m4a`'s name — the
closest true statement available, "an audio-only file AVFoundation
writes". A null there would hand a WAV to `ImageSequenceWriter` and report
a format this table advertises as an unsupported file type. But
**nothing runs a session any
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

**ProRes 4444, and what `alpha` means.** One row beside `prores_422`
(road map 2, phase 7) for the file whose next reader is another
application rather than a viewer: a master or an intermediate — a lower
third cut over somebody else's footage, a screencast going back into a
compositor — where the picture has to arrive with its transparency
intact. It shares 422's container, its colour and its
editing-master posture (no `moov` rewrite: nothing streams a ProRes) and
differs in exactly one thing, which is the whole reason it is a row: 422
cannot carry alpha at any bitrate, and neither can a delivery codec —
H.264 and HEVC have no alpha in the profiles `ExporterWriter` writes, so
a transparent canvas exported through one of them is a picture flattened
onto black with no way back. It sits AFTER 422 because a row's position
is an invitation and most exports of a finished timeline want the smaller
file. Its session name is `…AppleProRes4444LPCM` and is NON-null for the
LPCM rows' reason: a null is the ImageIO writer's cue, and a `mov`
handed to `ImageSequenceWriter` would be refused as an unknown image
container.

The resolved settings therefore carry **`alpha`**, and it is a
CAPABILITY of the encoding — "this row carries an alpha channel", true
for `prores_4444` and `apng` and nothing else — never "this project's
canvas is translucent". The settings are one flat object with the same shape for
every row, so a project-derived flag would report `alpha: true` on an
H.264, a GIF and a WAV, none of which has anywhere to put a fourth
channel; it is `audio`'s kind of fact, told `audio`'s way — what the file
can HOLD, not what this document happens to contain. It is a per-row
field and not a container question, which is where it differs from
`audio`: `Container::Mov` hosts 422 and 4444 alike, so a container-level
answer would have to be wrong for one of them. **`gif` is false and
`apng` is true**, which is the pair that reads as a mistake and is not:
both can show a transparent pixel, but APNG has a real fourth channel and
a pixel may be any fraction of opaque, while a GIF nominates ONE palette
index as transparent and has no partial value to store — so a flag saying
yes to both would license a promise of a translucent GIF. A canvas whose background
alpha is below 1 composites onto black in every other row, and this key
is what lets the sheet and the `export` tool say so before the file
exists.

**WAV and AIFF.** Two uncompressed rows beside `audio_m4a`, for the file
you hand to somebody else's tool rather than the one you send: 16-bit LPCM
at 48 kHz, which is what the mix is already decoded to (it is what the
ProRes row writes), so a WAV is that written straight out and an AIFF is
the same samples big-endian — the CONTAINER decides the endianness, and
`codec: "lpcm"` is what the writer branches on to reach LPCM settings at
all. Both are `video: false` with the audio-only row's size list and the
document's rate, and neither optimizes for network use: a RIFF or an IFF
file is a header followed by samples, with no index to relocate. 24-bit is
deliberately deferred — it would mean widening the decode settings the mix
is read through, which every other preset's encoder consumes, and a silent
format mismatch there is a file of noise rather than an error; a depth is
a request rather than a row when it comes, and needs measuring first.

**Loudness.** `loudness_lufs` (−70…0, BS.1770-4's own absolute gate at the
bottom) is the integrated target an export is normalised to, and
`peak_dbtp` (−20…0) is the true-peak ceiling the gain is capped against.
They are overrides on the bitrates' terms — no preset carries one, each
appears in the resolved settings only when asked for, each is accepted by
formats that cannot use it, and a value outside its range or of the wrong
type is an error naming it — with one exception the resolver states and
argues: **a `peak_dbtp` with no `loudness_lufs` is an error.**
Normalisation is gain-only with no limiter, so the ceiling exists solely
to cap a gain that a target computed; alone it would mean peak
normalisation, a different feature, and would otherwise be the first key
in this table accepted, echoed and silently inert.

**How an export is normalised** (the Swift half; `Loudness.swift`,
`Exporter.swift`, `ExporterWriter.swift`). The measurement is BS.1770-4 —
two K-weighting biquads run continuously over the programme, 400 ms
gating blocks at 75 % overlap, the −70 LUFS absolute gate then the −10 LU
relative gate, and true peak through the standard's 4-phase 12-tap
interpolating FIR — with the coefficients transcribed from the
recommendation at its published 48 kHz and the meter REFUSING any other
rate rather than filtering with the wrong numbers. It is arithmetic over
plain float buffers with no AVFoundation in it, which is what lets it be
checked against synthesized tones: the EBU Tech 3341 cases are specified
signals, so the self-checks need no fixture file.

An export is therefore **two passes, and the first one runs on every
export that has any sound at all** — not only a normalised one. The final
progress line and the `export` tool's result both report what the file
actually holds ("Peak −1.0 dBTP · −14.0 LUFS"), which is what makes the
target a claim anyone can check rather than a number repeated back; the
price is one extra decode, about a tenth of a picture export's wall time
and roughly a doubling of an audio-only one's, and the progress sheet says
"Measuring loudness…" while it happens rather than sitting at 0 under a
label that claims it is writing. GIF and APNG measure nothing: those
containers hold no audio track, which is the same fact the core reports as
`audio: false`.

Pass 1 builds its OWN composition. An `AVAudioMix` copy shares the
`MTAudioProcessingTap` its input parameters hold, and a tap carries
per-instance state (the compressor's envelope, the noise reducer's delay
line), so two readers over one mix would interleave into one tap's state;
a second build costs one more pass on the build queue and removes the
argument. It reads **32-bit float**, because Int16 saturates and a mix
hotter than full scale is exactly the material loudness normalisation
exists for — its true peak would otherwise be pinned at 0 dBTP by the
decode rather than by the signal. Nothing in this tree had asked an
`AVAssetReaderAudioMixOutput` for float before, so the request is MEASURED
with `canAdd` and falls back to the writer's own 16-bit dictionary if it is
refused (measured on macOS 26.5.1: it is accepted). Pass 2 is the ordinary
write, with the gain `target − measured`, capped so the shifted true peak
stays under the ceiling, applied to the decoded 16-bit samples on the way
to the encoder — rounding and saturating, never truncating, since
truncation biases toward zero and shows as DC on quiet material. **With
Loudness off the gain path is not entered at all**, so an unnormalised
export is byte-identical to a pre-phase one by construction rather than by
argument.

The limit that falls out of the two domains is worth stating rather than
discovering: the measurement is float and honest about a mix over full
scale, but the WRITE pass decodes to Int16, which saturates BEFORE the gain
is applied. So a mix that clips is measured correctly, normalised down, and
still clipped in the file — the gain cannot undo the decode. Turning a hot
mix down at the clips is the fix; the ceiling only stops the gain pushing
one INTO clipping.

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
only). Catalog: one tool per §6 op with the same name and arguments —
**each of which also takes `scope`, the envelope key of road map 2's phase
9** (§6), injected from ONE line in `AgentCatalog.tool(...)` gated on the
core's own `rc_op_names`, so a new op gets it for free and cannot drift, and
enforced by a fourth part of the startup parity check, which is the only
mechanism in the tree that would catch an op tool declaring none.
**All fifty-seven op tools PRINT those arguments rather than
restating them** (road map 7's D3·3 for the clip group, D3·4 for the rest):
`AgentCatalog.opTool(...)` takes the
tool's prose and a sentence per argument and merges the structure — kind,
constraints, closed vocabulary, required list — in underneath from
`rc_op_schemas`, so **the core says what an argument IS and the catalog says
what it is FOR**. Where a tool deliberately accepts more or less than its op
does — a bare-string body, the string spellings of a boolean, a null that
MEANS something, a range the core clamps to rather than refusing, a default
taken from the playhead, a list the tool will not take empty — the
difference is a row of `AgentCatalog+Declarations.swift` with the op, the
argument, what the app adds and why, and the schema declares it, so an agent
can SEE a shorthand rather than discover it. What still declares a schema of
its own is the twenty APP-STATE tools, which have no op to read one from.

**A fifth part of the startup parity check holds that identity up**
(`AgentServer+Parity.swift`, road map 7's D3·5). For every op tool the
declared argument names must be exactly the core's for that op, plus the
injected `project` and `scope`, plus whatever a declarations row names — in
both directions, so an argument the core has that no tool declares and an
argument a tool declares that no op has are each named with the op, the
argument and the side, and a declarations row naming an argument the core has
not got is named as stale. Because the catalog prints STRUCTURE and writes
only PROSE, the same part also complains about an argument that would reach an
agent with no description at all, and about a description written for an
argument the table has never heard of, which is how a misspelt prose key is
caught rather than dropped in silence. App-state tools are skipped by the same rule
part 4 uses — the core's own op list, which has no row for a tool with no op
behind it. What no comparison of two lists can see is a
CALL. A call's KEYS are compared to the tool's published schema at the
dispatch — the argument gate, kpgalligan/reelcut#21, for all seventy-seven
tools — so a name no tool published is refused naming the tool and what it
takes, where it used to be dropped in silence; and that an argument the
catalog prints is one a hand-written handler really reads is put to the
running binary by `tools/proof/op_argument_proof.py`, one left-out argument
per op.

The scope is read ONCE per call, at the dispatch, and an op with no `scope`
of its own follows the nest the app has OPEN — a call and the window agree
about which
container they mean, or `get_project` would list clips the very next op could
not name. An EXPLICIT scope outranks the open view. Plus
`set_scope {nest?, clip?}` (the mirror of the double-click and Clip ▸ Open
Nest, and what lets `render_frame` and `get_project` look inside a nest at
all; `clip` is the precise spelling, since a nest may be shown by two clips
at two different starts, and neither argument means the timeline),
`open_project {path}`, `new_project {path?}`, `import_media {path}` →
media id, `save_project`, `get_project` → the JSON, `set_playhead`,
`set_range`, `set_selection` and `undo` / `redo` (the view state and the
history are app state, not ops, but without a setter for each the "one
edit is one undo step" and "the in/out range scopes the export" properties
cannot be checked by driving the built app),
`import_captions {path, track?}` and `consolidate_media {}` (M3's two
§5.6 file features),
`record_screen {seconds, display? | window?, microphone?, system_audio?,
show_clicks?, rate?, size?, place?, path?}` (road map 3 — File ▸ New
Recording…'s mirror: the file lands as ordinary media at the playhead of
the target document, or as an untitled document rated at `rate` when
nothing is open; it reads the Screen Recording and Microphone grants
synchronously and NEVER prompts, and its refusal order is the caller's own
mistakes, then the grants, then the display or window lookup, which cannot
be asked without them; pausable from the menu bar's item while it runs,
the result then carrying `pauses` and `segments` — one entry per file,
ALWAYS present — with `duration` the TOTAL recorded and the top-level keys
the first segment's),
`detect_silence {clips?, threshold_db?, min_length?, padding?}` → the
quiet spans of the timeline and the scope they were taken over, which
`ripple_delete_ranges` then cuts — the one tool that reads a CACHE rather
than the model, and the only app-state tool that neither edits nor moves
anything (it is the sheet's own detector, so an agent and Clip ▸ Remove
Silences… propose the same cuts). A moment is quiet where every clip in
scope is quiet there, measured as the file's peak times the mix envelope
(§7.2), and two things are never in a candidate: a clip the mix has
SILENCED, which is dropped from either scope rather than read as quiet —
it covers its span while passing the test at every tick, so a muted music
bed would otherwise propose one cut across the whole song and take the
voiceover under it — and a NEST, whose sound counts toward the test but
which no candidate may intersect, because `Source::Nest` has no in point
and splitting a nest clip strands its tail (§4.4's round trip is how the
dead air inside one is reached),
`transcribe {clips?, language?, place?}` and
`export_captions {track?, path, format?}` (road map 2's phase 4 — the
mirrors of File ▸ Generate Captions… and File ▸ Export Captions…).
`transcribe` returns the cues in TICKS whether or not it placed them —
`place: false` is a read, like `detect_silence`, and registers no undo
step — and reports every named clip it could not read under `skipped`.
Two refusals are unlike anything else in the catalog. macOS gates speech
recognition, and this tool never asks: it REFUSES with the authorization
status named, because the system prompt needs a frontmost app and an
agent-driven one never is (`target`'s own fact, read across), so the grant
has to have been given once from the sheet. And its work can stop short of
the answer rather than fail: a run cut off by the framework's one-minute
ceiling reports `truncated` with the second it stopped at, instead of
presenting a partial transcript as the whole of what was said. `export_captions` never guesses its track: with no all-text track,
or more than one, it refuses and lists the candidates by id and name — the
posture `remove_media` and `export` already take when an answer is not
unique — and it edits nothing, so it registers no undo step either.
`render_frame {t, max_width?, path?, format?, burn_in_timecode?}` → a PNG,
JPEG or HEIC (the verification hook: the compositor renders offline through
an `AVAssetImageGenerator` over the same composition + video composition).
With no `path` and no `format` it writes a `.png` to a temporary file and
ends its text `Written to <path>.` exactly as it always has, which five
proof scripts read the path back out of; an explicit `format` wins over the
path's own extension and the extension is REPLACED rather than appended to.
The write is `FrameWriter`'s — the one function File ▸ Save Frame… calls
too, which is what makes those two files byte-identical by construction
rather than by luck, and the only way the line can be checked at all, since
no script can press a save panel. `burn_in_timecode` is the recipe option of
§7.3 and not an export override, and this tool is the only one that can
photograph a burn-in, and
`normalize_clip {clips, peak_db?}` (road map 2's phase 5 — the mirror of
the Audio section's Normalize button and Clip ▸ Normalize; it is a
composite the UI offers as one command, not an op, and it reports each
clip's measured peak and the volume it wrote, with what it could not
measure under `skipped`), and
`export {preset, path, size?, range?, video_bitrate?, audio_bitrate?,
loudness_lufs?, peak_dbtp?, burn_in_timecode?}` — the export sheet's
controls in the sheet's own vocabulary (all but the frame rate: the tool
exports at the document's, or on GIF and APNG at the format's cap), so an
agent export and a menu export can ask for the same file. Its result
carries what the file's sound MEASURED — integrated loudness, true peak and
the gain that was applied — for every export that has any, asked for or
not, which is `detect_silence`'s posture applied to the writer and is what
makes the ±0.5 LU claim checkable over MCP.
`burn_in_timecode` is the one argument of the nine that is not a setting:
it is a recipe option (§7.3), travelling beside the resolved settings rather
than inside them, because the override table ignores a key it does not
know — an option posted that way would vanish without a word and the tool
would report success on an un-burnt file. The result echoes it back for the
same reason.

**Lenient decoding is for what the CORE wrote; nothing a caller wrote is
decoded through it** (deepening D1): a patch, a colour, a region and a new
clip's text or shape go to the core as the caller's own object, and the core
is the one validator of what each may carry (§5.2, §6) — the agent door
checks only what the core cannot know, which is the target, the scope, an id
against the container it names, a time, and that a required argument was
passed at all.

Handlers use `performGroupedEdit` so off-event edits get their own undo group
(Rasterize's `AgentServer.performGroupedEdit`). Default port 4817; env
`RC_AGENT_PORT`; launch flag `-AgentServerEnabled YES`.

### 7.10 Rust module map

Crate `reelcut_core`, `crate-type = ["staticlib", "rlib"]`, deps `serde`,
`serde_json`, `serde_path_to_error` (the path a patch refusal names),
`tiny_http` (agent). Soft cap 600 lines per module; a new
concern is a new module with its own `impl Project` block.

| Module | Owns |
|---|---|
| `lib.rs` | declarations and re-exports only |
| `model.rs` | the §5.2 types and serde derives, and the serde defaults that say what an absent key means — the schema's SHAPE, and nothing else |
| `model_props.rs` | the §5.2 per-clip property types — `VideoProps`, `Crop`, `Shadow`, `ColorAdjust`, `Chroma`, `Filter`, `Reflection`, `BlendMode`, `AudioProps`, `Compressor`, `Duck`, and their enums, with their defaults: the schema's VOCABULARY where `model.rs` is its shape. Cut out under the size rule (road map 2, phase 2) and re-exported whole by `model.rs`, so every `crate::model::X` path still resolves. It has since paid the same rule THREE times itself, every time BEFORE the phase that owed it took anything on: the region types went to `model_regions.rs` in phase 3c, the text vocabulary to `model_text.rs` in phase 6 and the shape vocabulary to `model_shape.rs` in road map 5's E2, and it re-exports all three, so no path anywhere changed any time |
| `model_regions.rs` | the boxes drawn ON the picture — `Spotlight`, `ObscureRegion`, the `SpotShape` both are drawn with and the `MAX_OBSCURE` budget on the second. One concern, not three adjacent ones: they share one coordinate frame (`x`/`y` the region's CENTRE, an offset in SOURCE pixels from the centre of the layer's CROPPED rect; `width`/`height` its size in the same pixels — which is what carries a region with its layer through scale, move and rotation) and one shape enum. Cut out of `model_props.rs` under the size rule (road map 2, phase 3c) and re-exported whole by it, so every `crate::model::X` path still resolves; the FIELDS holding them (`VideoProps.spotlight`, `VideoProps.obscure`) stay with the video group |
| `model_text.rs` | the text vocabulary — `TextProps`, the `TextAlign` and `TextVAlign` it is placed by, the `Outline` and `Backdrop` drawn with it, and the `TextAnimation` and `TextAnimationKind` that reveal it. Cut out of `model_props.rs` under the size rule (road map 2, phase 6) and re-exported whole by it, and cut HERE because text is the one property group the model cannot MEASURE: every other group is quantities the core bounds, interpolates and solves against, while only the platform can lay a string out and the size comes back the other way through a cache (§5.3, §11). `TextAnimationKind`'s declaration order is NOT load-bearing — the recipe carries a reveal's kind by NAME — where `ObscureKind`'s and `BlendMode`'s are shader discriminants; the JSON spelling of every variant is, so a rename needs a migration step |
| `model_shape.rs` | the shape vocabulary — `ShapeProps`, the `ShapeKind` it draws, the `Stroke` around it, and the `Gradient`, `GradientKind`, `GradientStop` and `MAX_GRADIENT_STOPS` that fill it. Cut out of `model_props.rs` under the size rule (road map 5, E2) and re-exported whole by it, and cut HERE because it is `model_text.rs`'s seam read a second time: shape and text are the two sources the model only DESCRIBES, drawn on the CPU and keyed by the recipe's content hash, where everything left in `model_props.rs` is read straight into the compositor's uniform block. Nothing here is ever a shader discriminant — `GradientKind` may gain a kind at the END and nothing derives a number from the order, where `BlendMode`'s order IS the discriminant |
| `model_motion.rs` | the motion vocabulary (format version 8, road map 5's E2) — `Motion` and the `MotionEdge`, `MotionDuring`, `EdgeMotion` and `DuringMotion` it is made of. Its own module for a seam rather than for room: every other member of the video group is a quantity the compositor reads more or less straight, while these five say only what a clip should DO and the placement that comes out of them is computed at render time by `motion.rs`. Re-exported whole by `model_props.rs`; neither enum's declaration order is load-bearing, and both are closed |
| `model_query.rs` | reading a project: `Project::new`, id allocation, the `clip` / `track` / `media` / `marker` / `nest` lookups, `clips_on`, `duration`, `validate` with its nesting walk, the three source-window measurements (`content_length`, `source_head`, `source_length`) every placement op clamps against, and `source_size` — the source's pixel size when the model knows it, `None` for text and for a media, nest or shape with no positive size. That last one was TWO private readers, `edit_props.rs`'s and `edit_background.rs`'s stricter one, collapsed here by road map 5's T0f, so a source kind added to `model.rs` is answered once |
| `time.rs` | `Ticks`, `TIMESCALE`, `Fps`, frame snapping, timecode format/parse (non-drop `HH:MM:SS:FF` and `HH:MM:SS.mmm`) |
| `outcome.rs` | what an op ANSWERS (§5.5) — `Outcome`, with `Applied(Project)`, `Identity` and `Refused(String)`. An enum and not a side channel because a site that has not decided which of the three it gives does not compile, which is how the fourteen sites that used to throw a rule's sentence away were found (road map 7's D2). Its `Identity` doc is the ONE place that lists which refusals carry a sentence today, and the two families that stay identities on purpose |
| `edit.rs` | the op enum + serde, `apply(&self, op) -> Result<Outcome, String>`; **its module doc is the op table's SEMANTICS half**, where `op_table.rs` is its arguments, and it re-exports `OP_NAMES` at the path it has always had. `parse` answers an `Envelope` — the op AND the envelope's `scope` — which it takes out of the object in the pass that already reads `"op"`, because `Op` is internally tagged with `deny_unknown_fields` on every variant (an envelope key would be a typo to all fifty-seven) and serde does not support that attribute with `flatten`. `apply_op(&Op)` is unchanged and knows nothing about nests |
| `op_table.rs` | the op table as DATA (road map 7's D3): one row per op, one `Argument` per argument — name, `Kind`, required — and `OP_NAMES` as a projection of it rather than a list beside it. Its own module because the table is a PUBLISHED interface — every op tool in the catalog reads it rather than restating it (§7.9), and an `Argument` carries a `Bound` where the core REFUSES outside one, sourced from the constant that enforces it and never where the core merely clamps — and the `Op` enum and the fifty-seven-way dispatch are one implementation of it; a row carries no prose, no semantics and no default spelled twice, and `Kind` is closed with exactly one kind per answer serde can give, so every claim a row makes is one `core/tests/op_table.rs` can put to the decoder. Capped at 400 lines like any new module — `edit.rs`'s table exemption is not extended to it |
| `op_schema.rs` | the op table written as JSON SCHEMA — what `rc_op_schemas` publishes (road map 7's D3·2), one object per op whose properties are its arguments and whose `required` is the ones the decoder will not do without. A module of its own because a row changes when an OP does and this changes when the published DIALECT does, and the match over `Kind` is exhaustive so a kind cannot be added without saying what JSON it is. It publishes what an argument IS and never what it is FOR, an opaque object for a caller-authored patch (D1 is the one validator of what one may carry) and a `ZoomRegion`'s four declared members for the one caller-authored object the core does own, and no `additionalProperties` on an op, because the catalog merges `project` and `scope` in over it |
| `scope.rs` | editing INSIDE a nest — the envelope's `scope` key (road map 2, phase 9). Builds a VIEW project out of the nest, applies the op to it unchanged, and merges `tracks`, `clips`, `next_id`, `media` and `nests` back. Its own module because a scope is a change of CONTAINER rather than an op or a property of one, and because the whole of it is two pure functions and a refusal list, which belong nowhere near the semantics of any single edit. Three readings in it are measured rather than reasoned: the scoped nest's row stays in the view with its tracks and clips **emptied** (whole, it doubles every id in `validate`'s one uniqueness sweep; removed, it dangles every other nest's clip that shows it — the nest-inside-a-nest case the phase exists for); the nests write-back is **union first, orphans after**, because `unnest`'s `nest_is_shown` cannot see the parent's timeline clips from inside a view and would drop a nest a timeline clip still shows; and the caps and the depth are checked ONCE on the merged parent, which is why a scoped op has a wider `Err` arm than any other |
| `edit_clip.rs` / `edit_props.rs` / `edit_track.rs` / `edit_time.rs` | the §6 ops in `impl Project` blocks: clip placement; the five property patches (`set_video` / `set_audio` / `set_text` / `set_shape`, and `set_clip` for the clip's own name and label), each merged through `patch.rs` and then range-checked; tracks, markers, canvas, media; ripple, insert time, range delete, freeze |
| `patch.rs` | reading a caller-authored patch: `Group` (the vocabulary the four patches and `paste_attributes` share, and its per-group template), `check_keys` (the walk of keys and JSON kinds, array indices in the path), `merge_group` (the one read of a group patch — walk, deep merge, typed read back) and `check_group_patch` (the same for a group that is not merged into a stored one, which is what `edit_action.rs` composes an end patch's door out of). Every refusal names the dotted path and the offending value, and `COMPLETE_ENTRIES` is where the `video.filters` entry rule is stated. Cut out of `edit_props.rs` under the size rule in D1·2 for `props_check.rs`'s reason: what a patch may CARRY is a fact about the vocabulary, not about an edit, and nothing here is handed a clip |
| `props_check.rs` | the range checks every value written into a property group passes first — `check_video` / `check_audio` / `check_text` / `check_shape`, the `finite` / `in_range` family under them, and the bounds they check against (§4.3's numbers, which `actions.rs`'s `clamp_video` reads too) — cut out of `edit_props.rs` in phase 2 because a range check is a fact about the vocabulary, not about an edit; a patch and a `paste_attributes` copy run the same checks (`Project::check_group`) |
| `edit_edge.rs` / `edit_insert.rs` | the cutting moves that keep something fixed on purpose: `slip` and `roll` (the clip's place, and the pair's outer edges); `insert_clip` and `overwrite_clip` (the other tracks, and the timeline's total length) |
| `edit_action.rs` / `edit_nest.rs` / `edit_paste.rs` | the ops with a concern of their own: actions (the no-overlap rule, and `check_end_patch` — which groups an end patch may name and what a `null` in one removes, over `patch.rs`'s walk and read); `nest` / `unnest`; `paste` (making another document's clips fit) and `paste_attributes` (the same payload's earliest clip's property groups copied onto clips already placed — replaced whole, never merged) |
| `edit_canvas.rs` | the document's own shape — `set_canvas` and the three readers under it (`check_dimension`, the rescale of every clip and the re-snap of every time to a new grid). Cut out of `edit_track.rs` under the size rule (road map 7's D2·3), a pure move: a canvas is the document's frame, not a track, a marker or a media row |
| `edit_split.rs` | cutting one clip in two — `split_clip` and the two helpers only it has ever needed, `state_patch` and `narrow_to`. Cut out of `edit_clip.rs` under the size rule (road map 5, E2) and cut HERE because a split is not a placement: every other op there decides where a clip sits, while this one decides what the SECOND clip INHERITS — its base props from the evaluation at the cut, the actions that had not finished rebased to its own clip time with a straddled one narrowed to the keys it animated, and the halves of a preset anchored to the clip's two ends (`video.motion`'s rule, and `text.animation`'s). Every splitter in the crate routes here — `split_clips`, `split_under_playhead`, `clear_range` (so `ripple_delete_range(s)` and `lift_range`), `insert_clip`, `overwrite_clip` and `freeze_frame` — so a rule stated once is a rule they all obey |
| `edit_transition.rs` | the WRITE half of a transition: `set_transition`, `set_transition_duration`, `set_gained_transitions` (the rule that a clip which gains an overlap gains a transition), and road map 5 E1's `add_transition` and `set_transition_style` with the `TransitionAlign` their op argument is spelled in. Cut out of `edit_clip.rs` under the size rule and cut HERE because placement and transitions are different questions — `edit_clip.rs` decides where a clip SITS, this decides what happens where two of them meet. `transition.rs` is the READ half and nothing here restates it; `set_gained_transitions` is re-exported from `edit_clip.rs`, so every caller's path is unchanged |
| `edit_zoom.rs` | `add_zoom_action`, the screencast zoom (road map 2, phase 3b) — the one op whose substance is geometry rather than bookkeeping, which is why it is not a fifth function in `edit_action.rs`. **Its module doc is the placement equation**: the two frames (Q, `model_regions.rs`'s source pixels from the cropped rect's centre; C, canvas pixels) and the solve that turns a rectangle drawn on the picture into the `scale` / `x` / `y` an action's end patch carries, rotation and crop included. Composes `add_action` + `set_action` + `set_action_end`, so a drag is one undo step and every `add_action` refusal is inherited rather than copied |
| `edit_background.rs` | `add_background` and `add_blurred_background`, what goes BEHIND the picture (road map 2, phase 6c) — a plate (a colour, or an image) or a blurred copy of a clip, each ONE clip on a NEW track at index 0, so there is no overlap to check and one undo step takes it all away. They are core OPS rather than app-side composites, which the road map had planned, because the composite carries a constraint no half of it states: the blurred copy must show the same frames as its original, which means its source WINDOW, where `add_clip` gives the whole media and `duplicate` lands the copy somewhere else on the same track. In the core it is `clip.clone()` with six VIDEO fields overwritten — `scale`, `x`, `y`, `crop`, `filters`, `blend` — over vocabulary the app lacks: the source's pixel size, `edit_clip.rs`'s `fill_scale` and the `SCALE_MAX` clamp on it. `insert_clip`, `overwrite_clip` and `add_zoom_action` are the standing precedent for that rule |
| `actions.rs` | evaluation and interpolation, `clip_state(clip, t)`, and `clamp_video`, the last line of defence §5.4 describes. §5.4's LIST rule is stated here once and applies to every array of objects in the schema (`video.filters`, `video.obscure`), neither of which carries a line of its own code; the widened discriminant set is confined to list ENTRIES, so `video.spotlight`'s animation is what it has always been. `clamp_video` also carries the one bound that is not a range — a NEST clip's evaluated `blend` is forced to `normal` (format version 6) — because `set_action_end` never sees the clip (it checks the vocabulary, and `multiply` is a legal mode), and closing it in the evaluator closes the recipe, `clip_state` and both export writers at once, which no per-op check can |
| `transition.rs` | overlap detection, the overlap rule, progress at *t* |
| `evaluate.rs` | `composition_plan()` (A/B assignment, instruction tiling) and the `assign()` the recipe shares with it |
| `recipe.rs` | `frame_recipe(t)`: the layer list at one instant — like every walk over what plays, it consumes `nest.rs`'s instances — and the keys of each layer in it, `blend` included. It is also where a clip's `video.motion` becomes placement, through the two `motion::apply` calls in `layer` and `frame_of` (§5.3); no layer key was added for it. `content_hash` and the FNV under it stay here and are `pub(crate)`: a SHAPE layer hashes its description through the same function, so the hash is the recipe's texture-cache primitive rather than a text concern. Phase 7 added `RecipeOptions` (what a caller wanted besides `t`; `frame_recipe(t)` is `frame_recipe_opts(t, defaults)`, one implementation so the two cannot drift) and `RecipeLayer`, the twenty layer keys written in ONE place — the burn-in is a second producer of layers, and a copied skeleton would drift silently, since `RecipeLayer.init(from:)` defaults a missing key with no diagnostic |
| `recipe_text.rs` | what a text layer SHOWS at one instant: the `reveal`, its phase and its kind (§7.3), computed in the core so everything that draws reads one description, folded into the layer's content hash so a per-frame picture cannot be served a stale texture, and assembled into the layer's `source` object by `text_source`. Cut out of `recipe.rs` under the size rule (road map 2, phase 7) and re-exported by it, so `crate::recipe::text_source` still resolves, and cut HERE because placement is the same question for every layer while text is the one kind that is not finished when its placement is — the model can only state an intent (§5.3, §11), and an ANIMATED intent is not even fixed. `text_source` takes a description, a clip time and a duration and nothing else — no clip, no instance — so a text layer the core synthesizes is a text layer like any other. The cut paid for itself at once: `burn_in_layer`, the timecode layer `burn_in_timecode` appends, is here, with no animation (so `Reveal::WHOLE`), a fraction-of-the-height placement rather than a bottom anchor, and the non-drop and project-time readings §7.3 records |
| `motion.rs` | `video.motion` turned into PLACEMENT (§5.3): the two edge tables and the during table of road map 5 §5b, the tent rule, the `rem_euclid(360)` reduction, the visible-centre pivot and the slide geometry. `apply` takes the EVALUATED props, the clip time, the clip's own duration, the source's pixel size and the container's canvas and answers the same props with five fields moved; `recipe.rs`'s `layer` and `frame_of` are its only two callers, which is what keeps everything that EDITS reading the clip un-moved (§5.4). It never trusts the file — a degenerate duration, period or amount is inactive or clamped, and no NaN reaches the recipe — and it SHORT-CIRCUITS to `video.clone()` when no slot is running, so a frame past an arrival is byte-identical to the same clip with no preset |
| `nest.rs` | flattening a nest: the walk that turns a nest clip into the clips it stands for, and the transform they inherit |
| `audio.rs` | envelopes: fades, volume actions, ducking, mute and solo — solo judged per container (the timeline, or a nest's own tracks) in `Voice::of` against that container's track set, never in the plan |
| `audio_duck.rs` | ducking — the one term of the envelope that comes from ELSEWHERE: `Ducker`, `duck_gain` (the attack / hold / release multiplier at a tick) and `Project::duckers`, the walk over the flattened timeline that collects them. Cut out of `audio.rs` under the size rule and cut HERE because every other factor `audio.rs` folds is a property of the voice being measured, while a duck is imposed by a clip on some other track and is computed from a different input — the instances, not one composition track's segments. `Ducker` is re-exported by `audio.rs`, so `crate::audio::Ducker` still resolves |
| `audio_crossfade.rs` | the transition crossfade (format version 7, road map 5's E1) — `crossfade_gain`, the constant-power multiplier at a tick, and `crossfade_breaks`, the ticks the curve has to be sampled at for it to survive coalescing. `audio_duck.rs`'s seam one step along: a duck comes from a clip on another TRACK, a crossfade from the neighbour this clip OVERLAPS, and neither is a property of the voice being measured. Both halves in one module because they have to agree — a gain with no breakpoints under it is flattened into one ramp and the constant-power law degenerates into the equal-gain one it exists to avoid |
| `snap.rs` | candidates and `resolve` |
| `format.rs` | `RC_FORMAT_VERSION`, the `MAX_*` reader caps (`RC_MAX_*` in the header), read-any-version / write-current |
| `export.rs` | settings resolution: `Project::export_settings`, the one thing that reads a canvas, a duration, a rate and an override and meets a preset row against them. Still the file whose module doc explains the whole export design, and it re-exports `preset` / `presets` (beside `describe`) at their old paths |
| `export_overrides.rs` | how an override value is READ and REFUSED, where `export_table.rs` is the table and `export.rs` the resolution: `describe`, the overrides object itself, and the readers for a positive integer, a boolean, a rate, a range and a decibel figure, each refusing with a message naming the key and the value. Cut out of `export.rs` under the size rule (road map 2, phase 5) and cut THERE for `props_check.rs`'s reason — how a value is spelled is a fact about the vocabulary, not about the resolution. `describe` was never an export function (five edit modules import it for their own messages), so `export.rs` re-exports it under the old path |
| `export_size.rs` | `export_sizes(preset)`: the Size popup's rows — the document's size, an image format's cap, the standard sizes fitted to the document's aspect by the short-edge rule — and `fit_within`, the rule for what a size means on an image format, which `export_settings` applies too |
| `export_table.rs` | the rows themselves — the `Container` enum with the four questions a container answers about ITSELF (extension, UTI, whether a leading index is worth rewriting, whether it can hold sound at all), `Preset`, the `PRESETS` set one row per encoding in menu order, and the `preset(id)` lookup both resolvers share. Cut out of `export.rs` under the size rule (road map 2, phase 7 — the second cut that file has paid, after `export_overrides.rs`) and cut HERE because everything in it is a constant no project can influence, where `export_settings` is the only half handed a `&self`; `export.rs` re-exports both functions, so `crate::export::presets()` and `crate::export::preset(id)` resolve as they did |
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
    Cargo.toml        # reelcut-core; lib name reelcut_core; serde, serde_json, serde_path_to_error, tiny_http; lto
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

Rules carried over verbatim: pure ops, which here answer three arms rather
than Rasterize's `Option` (§5.5); the three-file lockstep (`ffi_*.rs` →
header → `ReelCore.swift`)
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
| ⌫ | Delete the selection, leaving a gap — or LIFT the in/out range when nothing is selected |
| ⌘⌫ | Ripple delete (selection, or the in/out range) |
| ⇧⌘F | Freeze frame |
| ⌥⌘D | Detach audio |
| ⌥⌘K | Add action at playhead |
| M | Add marker |
| I / O / ⌥X | Set in / set out / clear range |
| N | Toggle snapping |
| T | Add text clip at playhead |
| C | Crop mode on the selected clip |
| Z | Region mode on the canvas — drag a rectangle over the selected clip to zoom to it (⇧ fills instead of fits), Esc cancels. Z again disarms it, and so does moving the selection: one key in and out, because a modal overlay that has lost focus can no longer be dismissed by Esc |
| ⇧Z | Fit timeline |
| ⌘= / ⌘- / ⌘0 | Zoom in / out / fit (canvas, or timeline when focused) |
| ⇧⌘N | New track |
| ⇧⌘I | Add media… |
| ⌘G / ⇧⌘G | Nest / un-nest (M3) |
| ⌘↓ / ⌘↑ | Open / close nest (road map 2's phase 9) — go inside the selected nest clip, and come back OUT one level. Two items rather than one toggle, unlike ⇧⌘P: in and out are different distances, since a stack can be eight deep, so a single checkmarked row could not say what it would do |
| ⇧⌘R | Rename the selected clip — an inline field over its name strip |
| ⌥⌘V | Paste Attributes — the copied clip's look onto the selection |
| ⌘E | Export… |
| ⌥⌘E | Save Frame… — the frame under the playhead as a PNG, JPEG or HEIC still (road map 2's phase 7a). Export…'s still-image sibling, under the same letter |
| ⌥⌘N | New Recording… — the recorder panel (road map 3). The same item reads Stop Recording while one runs, paused included, and stops it; a nil-target action on `AppDelegate`, so it resolves with no document open, as New Project does. Pause Recording and Resume Recording have no menu item and no key — they are the status item's rows (R2) |
| ⌥⌘I | Toggle inspector |
| ⇧⌘P | Preview Window — a second window showing the same picture as the canvas, with no overlay (road map 2's phase 8b). A TOGGLE: the item carries a checkmark and the key both opens the window and puts it away |
| `,` / `.` (⇧ ×10) | Nudge the selection one frame |
| ⌥-drag clip | Duplicate |
| ⌥⇧-drag clip | Slip — the source under a fixed clip |
| ⌥-drag clip edge | Rate stretch |
| ⌥⇧-drag clip edge | Roll — the hard cut that edge sits on |
| Double-click an empty lane span | Close that gap |
| Double-click a clip | Rename it in place — EXCEPT a nest clip, which opens (road map 2's phase 9); rename it with ⇧⌘R, Clip ▸ Rename… or the Clip tab's header field |
| Click the breadcrumb | Come out one level, while a nest is open — the corner over the track headers, which is inert otherwise |
| ⌥-drop / ⇧⌥-drop from the Media tab | Insert / overwrite at the drop |
| ⌥-click a track header | Select every clip on that track |
| ⌘-drag | Suppress snapping |

**Proposed, not yet bound** — the keys `designs/reelcut-roadmap-2.md` asks
for, kept here so a phase that binds one checks this table for a conflict
first and then promotes its row into the one above. A row here is a claim on
a key, nothing more.

| Keys | Action | Phase |
|---|---|---|
| — | Nothing. Phase 9 took the ⌘↓ / ⌘↑ this table claimed for it, for Clip ▸ Open Nest and Clip ▸ Close Nest, and the row has been promoted into the bound table above. Carrying a modifier does NOT keep either off the first responder — every main-menu key equivalent is offered the key-down before the window dispatches it, and what a modifier changes is only WHICH field-editor binding it displaces (here `moveToBeginningOfDocument:` / `moveToEndOfDocument:`). So the pair is validated DEAD while text is being edited, the Delete pair's precedent — otherwise ⌘↑ in an inline rename would leave the nest and discard the open field | — |

Menus: File (New Project, New Recording… (road map 3 — directly under New
Project with no separator, because both make a document out of nothing),
Open…, Open Recent, Close, Save, Save As…,
Add Media…, Import Captions… (M3), Generate Captions… and Export
Captions… (road map 2's phase 4 — the three caption items sit
together, in the order a caption track comes into being and leaves again,
and none of them takes a key equivalent), Consolidate Media… (M3),
Export…, Save Frame… (road map 2's phase 7a — the frame under the playhead
written as a PNG, JPEG or HEIC still, at ⌥⌘E because it is Export…'s
still-image sibling and belongs under the same letter; the format is chosen
in the save panel's own accessory view rather than in a sheet, and the panel
says which of the three keeps the canvas's alpha, because phase 7b makes a
transparent canvas reachable and JPEG cannot carry one — it flattens onto
black. One writer serves the menu item and `render_frame` alike
(`FrameWriter.swift`), which is what makes the two produce the same bytes for
one frame rather than merely being meant to)),
Edit (Undo, Redo, Cut, Copy, Paste, Paste Attributes, Duplicate, Delete,
Ripple Delete, Insert at Playhead, Overwrite at Playhead, Select All,
Select After Playhead, Select All on Track), Clip (Split, Trim Start, Trim
End, Freeze Frame, Detach Audio, Normalize (road map 2's phase 5, beside
Detach Audio because those two are the menu's only sound commands; no key
equivalent, and it duplicates the Audio section's button deliberately —
a command reachable from a pane alone can be lost), Add Action, Speed…,
Close Gap, Remove
Silences…, Transition ▸, Motion ▸ (In ▸ / Out ▸ / During ▸, each the kinds
and None; no key equivalent), Add Background ▸ (Solid Color · Image… — road map
2's phase 6c, a submenu rather than one dialog because the two are
different commands: the colour takes no dialog at all and is re-coloured
afterwards in the Shape section's Fill row, which is also how a
full-canvas gradient is reached, while the image needs a file chooser) and
Add Blurred Background, in a group of their own since neither edits the
selection — both put a clip on a new back-most track — and neither takes a
key equivalent, Rename…, Label ▸ (the six colours and None),
Nest, Un-nest, Open Nest ⌘↓, Close Nest ⌘↑ — road map 2's phase 9, in the
grouping group because going inside a nest is the third thing you do with
one), Track (New Track,
Remove Track, Remove Empty Tracks, Hide/Mute/Lock/Solo), Mark (Add Marker,
Set In, Set Out, Clear Range, Next/Previous Marker), View (Zoom, Fit,
Snapping, Safe Areas, Inspector, Timeline Track Height, and — road map 2's
phase 8, in a group of their own after a separator because both are about the
PREVIEW rather than about the editor's panes — Preview Quality ▸ (Full · Half ·
Quarter, a tagged submenu with a checkmark for the current row and no key
equivalents: it scales the render size of the PLAYER's video composition alone,
always at the canvas's exact aspect ratio, and export and `render_frame` are
unreachable from it) and Preview Window ⇧⌘P (a second `AVPlayerLayer` on the
same player in an `NSPanel` — a panel because a titled window would become MAIN
and every ⌘-item whose action lives on the editor would stop resolving while
the preview was focused; its window sets `isExcludedFromWindowsMenu` for the
export queue's reason and autosaves its frame, which the queue's deliberately
does not, so it stays on the display it was put on)), Window (Minimize,
Zoom, Export Queue — road map 2's phase 7e, the export sheet's Add to Queue
button's other end, with no key equivalent because §9's "proposed, not yet
bound" table claims no row for it and every bare letter belongs to the
editor's own `keyDown`; the queue's window sets
`isExcludedFromWindowsMenu`, since this menu is `NSApp.windowsMenu` and
AppKit would otherwise list it a second time under its own title — Bring All
to Front), Help.
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
  keeps Rasterize's synchronous AppKit discipline. Speech recognition did
  NOT earn a second exception when it landed: `SFSpeechRecognizer`'s
  callback API is complete for what a transcription needs (a result handler
  per hypothesis and a final one, plus a delegate method per second of
  audio processed for the progress bar), so `Transcriber.swift` uses it and
  the rule stands. `SpeechAnalyzer`, the macOS 26 replacement, is
  `async`-only and would earn the argument again — but only when the
  deployment target moves, and then as one more named file, never as a
  general licence. Screen recording (road map 3) did not earn one either:
  every ScreenCaptureKit and AVFoundation capture call it needs has a
  completion-handler form, and `ScreenRecorder` uses those.
- **Transcription reads EXTRACTED audio, not the media file.** Each clip's
  own source window is written to a temporary mono 16 kHz WAV and the
  recogniser is handed that. Whether `SFSpeechURLRecognitionRequest` can
  read an arbitrary `.mov` is a question nothing in the framework's
  documentation answers and nothing here can measure — the grant needed to
  try it cannot be obtained by an app that is never frontmost — and a
  design that works on the `say -o` fixtures and fails on every real clip
  is the worst failure shape available. It pays twice besides: the work is
  bounded to what the timeline uses (a 20 s clip of a 30-minute recording
  is 20 seconds of recognition), and the time mapping loses its `in` term
  entirely. The framework's roughly one-minute ceiling per task is
  REPORTED, not chunked around; chunking at the silences `detect_silence`
  already finds is the recorded follow-up.
- **Media is referenced, not copied**, by path + bookmark (not
  security-scoped; the app is not sandboxed). Consolidate is M3.
- **Screen recording is IN; camera recording and callouts stay OUT** (road
  map 3, reversing §1's day-one non-goal). A screen recording is the input
  the whole product was shaped around; camera capture is a second capture
  stack and callouts are a metadata format plus an Input Monitoring grant.
  What ScreenCaptureKit draws into the pixels for free — the cursor, and
  a ring around each click — is taken; nothing is reconstructed afterwards.
- **A recording is ordinary media.** The recorder writes a file and the app
  imports it through exactly the path File ▸ Open and Add Media… use
  (`adoptImported`, the two-try placement). The model learns nothing: no
  source kind, no flag, no schema bump. Every op, cache and export treats a
  recording clip as the media clip it is.
- **The file lives in `~/Movies/Reelcut Recordings/`**, named by date and
  time, never in the package and never in the temporary directory: an
  untitled document has no package (§5.6), and a recording is ORIGINAL
  footage, so the one place it may not go is where a cache is regenerable.
  Consolidate carries it in on the same terms as any other file.
  `-RCRecordingFolder` overrides the folder for a proof.
- **The canvas takes the recorder's RATE; the media record takes the
  file's.** ScreenCaptureKit delivers a frame only when the screen changes,
  so its files are variable-rate and the probe honestly reports something
  like 24981/1000 (measured); the untitled document is built at the 30 or
  60 the panel asked for, because that is the grid the person chose, and
  `set_canvas` is NOT used for it afterwards — an untitled document's
  first project is not an undo step, and the rate is part of what the
  document IS.
- **The panel asks for the grants; the tool never does.** `Transcriber`'s
  rule for two grants: Screen Recording (`CGPreflightScreenCaptureAccess`
  reads, `CGRequestScreenCaptureAccess` asks) and Microphone
  (`AVCaptureDevice.authorizationStatus`, `requestAccess`). The microphone
  status is read BEFORE any `AVCaptureDeviceInput` is constructed, because
  that initializer prompts on its own. `record_screen` reads and refuses by
  name with the fix in the sentence. The built app needs BOTH the plist
  usage key and the hardened-runtime entitlement
  `com.apple.security.device.audio-input` for the microphone; Screen
  Recording needs neither.
- **Microphone and system audio are two sources and stay two FILES.**
  Measured (road map 3's R0): with both on, `SCRecordingOutput` writes ONE
  stereo track that is their SUM, inseparable and clipping when both are
  loud — the one thing a screencast cutter cannot repair afterwards. So the
  microphone is never on the recording stream; it is an `AVCaptureSession`
  writing its own `.m4a` beside the movie, started first in the same
  run-loop turn, and it lands as its own clip on its own track at the
  offset the two did-start callbacks measured (a per-SEGMENT number since
  R2 — R0 q7 measured a different one at every resume — never a constant).
- **Undo of Add Recording leaves the files on disk**, exactly as undoing Add
  Media… does. A recorder that deleted footage on ⌘Z would be the only
  destructive undo in the app. For a recording that opened as a new project
  the first segment IS the document and has no step; the rest is one step,
  Add Microphone (one segment with a voice) or Add Recording Segments.
- **A paused recording is a SEQUENCE of files over ONE stream** (road map
  3's R2, 2026-09-12). ScreenCaptureKit has no pause: the only lever is
  removing the recording output — its file closes — and adding a fresh one
  to a new file while the stream keeps capturing, measured (R0 q7) at
  5–25 ms to close, 8–10 ms to start and 57 fps through the pause; the
  microphone's writer is stopped and restarted per segment on its one
  session. Each segment is named by its OWN start time, carries its own
  measured offset, and lands as a clip touching the previous one; the model
  still learns nothing, and nothing joins the files afterwards.
- **The recorder panel goes away when a recording starts, for every
  source, and comes back only with something to say** (R2). The menu bar's
  status item is the recording's whole chrome — Pause Recording and Stop
  Recording, then Resume Recording and Stop Recording while paused — and the
  panel returns after the landing only when it was on screen as the
  recording began and the landing's note is non-empty (a stop from the
  SYSTEM's own indicator — Reelcut's item's Stop writes no note — a closed
  target, a microphone problem, a refused resume, a file the landing could
  not place, a failure). ⌥⌘N shows it again; while it is hidden, the quit
  guard opens the item's menu rather than beeping.
- **The silence detector's second signal is a voice-activity model, and
  the model is Silero VAD v6.2.1 as a Core ML program** (road map 4's S0/S1).
  It is the app's first ML asset. It is vendored COMPILED
  (`silero_vad.mlmodelc`, 640 KB, FP16) with its MIT notice and a
  provenance file naming the upstream tag, the conversion's repository and
  the download's revision, so a re-conversion from the MIT upstream with
  coremltools is a documented option and not the only route. Core ML is the
  runtime; nothing else is added.
- **Edges come from the model's own 32 ms grid, inward; the level rule is
  the judge only for media that hold no voice.** No adaptive threshold, no
  level-based edge refinement: the measured edge error is inside the
  padding the feature already keeps.
- **The probabilities are a per-media CACHE, never computed at feature
  time.** `cache/speech/<media id>.bin` beside `peaks/`, stamped and marked
  on the same terms (§5.6), written by `MediaImporter`'s pass — so the
  model runs where `await` is already allowed and `MLModel.prediction` is
  synchronous anyway. **No new `async` exception, no `@available`, no
  deployment-target change.**
- **Voice is the default mode** for the sheet and for `detect_silence`;
  level stays as a mode and as the fallback, unchanged in its arithmetic,
  so a project whose sound is tones (road map 2's phase-3 fixtures are)
  detects exactly what it did.
- **No network model in the silence path.** A transcript-level edit is
  where such a model would go, and that is a separate item on a later list.
- **R5-1 — Effects are closed vocabularies, never a runtime.** Every
  transition kind and motion preset is an enum variant or a struct the core
  range-checks, the recipe carries, the MCP catalog mirrors and the one
  compositor draws. There is no package format, no user shader, no
  expression language — which is why neither road map 5 phase adds a Metal
  pipeline.
- **R5-2 — A transition's sound is a constant-power crossfade, on by
  default for NEW transitions and absent from old files.** The overlap a
  person adds a transition at is two different moments — a Remove Silences
  cut, a jump between takes — which is uncorrelated material, where
  constant power holds the level and equal gain dips 3 dB. A version-6 file
  has no `audio` key and sounds exactly as it did; every transition the
  core mints from version 7 on says `audio: true, curve: ease_in_out`. One
  constructor, `Transition::minted`, is the only place those two values are
  written.
- **R5-3 — `add_transition` builds the overlap from handles, clamps the
  duration, and never moves a third clip.** A shorter transition is the
  same edit at a size the media allows; a gap closed part-way
  (`close_gap`'s refusal) is a different edit. Not being at a hard cut is a
  wrong ARGUMENT (`Err`), because the op is pointed at one cut by a caller
  who meant that cut — unlike `roll`, which a drag can reach at any edge;
  having no handle is a domain refusal (`Outcome::Refused`, §5.5 — it
  says so in its own sentence since road map 7's D2·3).
  **Amended 2026-09-16, by the user: when there is no handle, OFFER to
  shift.** Two whole files placed back to back — the most common screencast
  cut — have no handle on either side, so the rule above left Clip ▸
  Transition ▸ with nothing to do but refuse. `add_transition` gained
  `ripple`, and the refusal sheet a button that sends it: the incoming clip
  and everything at or after the cut on every unlocked track slide left, the
  timeline gets shorter, and the tracks stay in sync (the user chose
  "everything after", over "the rest of this track" and "just the clip").
  The rule above still holds for the default form, which is still what the
  menu tries first: a third clip moves only when a person has been told it
  will and said yes, or an agent passed `ripple` by name.
- **R5-4 — Motion is a presentation term.** `video.motion` is stored in the
  model and drawn by the recipe, but `evaluate_clip`, `get_project`, the
  inspector's fields and every edit read the clip un-moved. It is the
  second place the recipe draws what the model does not say — the first
  being the forced `normal` blend under a transition (§7.3). It is not an
  animation target: an action cannot animate it, and a file that tries is
  drawn with the base motion.
- **R5-5 — Motion is a pure function of clip time.** No seed, no wall
  clock, no previous frame: `render_frame` at a tick is byte-identical run
  after run, preview and export agree, and two clips with the same preset
  at the same clip time are displaced identically.
- **D2-1 — A refused op says why in the CORE's words; a tool still names an
  argument the caller left out.** Deepening D2 gave every rule that refuses
  a sentence of its own and deleted the app's copies
  (`designs/reelcut-roadmap-7.md` §4–§5), so no agent handler trial-applies
  an op in order to write a reason. The line between the two, drawn at D2·4
  because six handlers answer a caller before the core sees the call: **a
  check that predicts a RULE goes; a check that names the CALL stays.**
  `set_transition_style` with neither key, `ripple_delete_ranges` with an
  empty array, and `set_track`, `set_marker` and `set_canvas` with no keys
  are the second kind — the core answers an identity, correctly, and an
  identity says only that the project is already in that state, which tells
  a caller who forgot an argument nothing it can act on. So is
  `normalize_clip` with nothing it could MEASURE: the peaks are in the
  package's cache and not in the model, so that is a fact the core cannot
  have (§7). **This amends the seventh Implementation Decision of
  kpgalligan/reelcut#8**, which had listed `set_transition_style`'s refusal
  and `normalize_clip`'s check among the deletions; the first is one of five
  of a shape, and deleting one of five would leave the tool surface
  inconsistent for a caller.
- **D3-1 — The core says what an argument IS; the app says what it is FOR.**
  Deepening D3 made the op table a published interface
  (`designs/reelcut-roadmap-7.md` §7–§9): `core/src/op_table.rs` holds one row
  per op and one `Argument` per argument — name, `Kind`, required — and
  `rc_op_schemas` publishes it as JSON Schema, which all fifty-seven op tools
  PRINT instead of hand-writing a `"type"`, an `"enum"` or a `required` list.
  The app keeps what the core cannot know: the sentence naming the menu item a
  tool mirrors and what the argument is for. **Where the line falls in the
  hard cases**, drawn at D3·3 because two tools would otherwise have got worse
  on the way through: a bound the core REFUSES outside is the core's and is
  published from the table, sourced from the constant the refusal is written
  against and never retyped; a bound the core merely CLAMPS to, a null that
  MEANS something, and a bare-string shorthand are the APP's, each a row of
  `AgentCatalog+Declarations.swift` carrying the op, the argument, what the
  app adds and why. The direction is the whole of the rule: **a schema
  narrower than what a tool accepts costs a caller nothing; one wider is a
  promise the app breaks.** This is what makes the *One JSON op entry point*
  decision above true as it was written — "the MCP catalog is the same table"
  — where until D3 the catalog was a hand copy of one.
- **#21 — A call is checked against the schema its tool published, at the
  door, for every tool.** The agent handlers read a caller's arguments by
  name and build the op, so an argument no handler read collided with
  nothing and was dropped in silence — an optional argument misspelt, an
  argument no op takes, a required one misspelt and reported as the right
  name missing. The fix is one comparison at dispatch
  (`AgentServer+Gate.swift`): the caller's keys against the tool's published
  `inputSchema`, every stranger refused naming the tool, the strangers and
  the whole of what the tool takes. Two choices, taken with the fix
  (`designs/reelcut-roadmap-7.md` §11.6): it covers **all seventy-seven
  tools** and not the fifty-seven ops, because the app-state tools have the
  same defect and the comparison reads a published schema either way; and it
  speaks the **app's** sentence rather than the core's serde wording, because
  twenty tools have no core sentence to borrow and `noSuchId` set the house
  style. **What it deliberately is not** is the handlers forwarding a
  caller's op to the core unread — §11 measured that at 21 named refusals, 6
  app-state defaults, 11 per-op transforms and one correctness guard, and the
  gate buys the same contract and gives up none of them. The same class one
  reader down went with it: a whole number is read exactly, so `3.7` where an
  id belongs is refused and never truncated to 3.

- **#22 — A media clip's window stays INSIDE its file, on the grid.** A
  clip's duration is written from its source at three sites —
  `whole_media_length` (what `add_clip` gives a clip, and therefore how much
  room `insert_clip` opens and how much span `overwrite_clip` clears),
  `set_canvas`'s fps `resnap`, and `trim_end`'s tail clamp — and all three
  snapped to the NEAREST frame, which rounds UP past the end of the file
  whenever the last frame is more than half a frame short. The plan then
  handed `evaluate.rs` a segment whose `source_duration` was the clamped
  remainder rather than the clip's duration, so the rate came out just under
  1 and AVFoundation RESAMPLED material nobody had asked to retime. All
  three now snap DOWN: a media clip satisfies `in + duration × speed ≤
  media.duration` by construction and its segment plays at rate exactly 1.
  Three costs, taken: a whole-file clip may end up to one frame before its
  file's last sample; a timed media shorter than one canvas frame cannot be
  a clip at all and `add_clip` says so in a second `Err` sentence naming the
  frame; and an fps change may shorten a whole-file clip by a frame. The
  shape DECLINED was holding the last partial frame — carrying a sliver
  through the plan and the compositor so the file's final sample always
  plays — which buys a sub-frame of picture at the price of a sub-frame time
  in the model, and nothing sub-frame lives in the model (§6). What the rule
  does NOT cover: `set_speed` and `rate_stretch` (a nearest-snapped duration
  times a rate can still outrun by a rounding), `paste` and `unnest`'s
  re-snaps, and `add_background`'s timeline-length plate — the source-window
  candidate of `designs/reelcut-roadmap-7.md` §10, where they are measured
  together. `evaluate.rs`'s clamp stays: hand-written JSON, a version-8 file
  minted before this, and the one-frame floor `resnap` cannot go below still
  reach it. No persisted field changes, so `RC_FORMAT_VERSION` stays 8.
