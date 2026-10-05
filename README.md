# Reelcut

A native macOS video editor in a screencast editor's shape: open a movie, arrange it on
layered tracks over a fixed canvas, trim, split, annotate, animate, export.
Swift/AppKit UI over a Rust core — the core decides, AVFoundation and Metal do.
Apple Silicon, macOS 26+.

The opening flow is the point. File ▸ Open on a `.mov` or `.mp4` (or a drop on
the Dock icon, or the welcome window's Open Video…) creates an *untitled*
project sized and rated to that file, with the file as the first clip on
Track 1, ready to cut. Save then writes a `.reelcut` package next to the
source.

The full design and implementation spec is `designs/spec/`, one file per
section, indexed by its `README.md`. It is normative: §5.2 is the project
schema, §6 the op table, §7 the architecture.

## What it does today

- **One kind of track.** Every track holds any clip — video, audio, image,
  text, shape. Tracks stack back to front; `tracks[0]` is the back.
- **Screen recording.** File ▸ New Recording… (⌥⌘N, or the welcome window's
  third button) opens a small floating panel: a display or a window (the
  system picker), whether Reelcut's own windows are in a display recording
  (left out by default), a microphone with a live meter, system audio, click
  rings, 30 or 60 fps, point or pixel size, and where it lands — a new project, or
  an open document at its playhead. A 3-2-1 countdown, then a red dot with
  the elapsed time in the menu bar carries Pause, Resume and Stop; File ▸
  Pause Recording pauses and resumes too. A paused recording is one file
  per stretch; a stretch whose file cannot be read is left out, and the
  note names it and where its files are — and its microphone, when it
  reads, still lands in the stretch's place. The file is written to
  `~/Movies/Reelcut Recordings/` and imported as ordinary media (undo
  removes the clip, never the file); a microphone is a second file on its
  own Microphone track, aligned to the picture. A new project takes the
  rate you chose; a screen recording's own rate is whatever the screen did.
  The first time you press Record the app asks for the Screen Recording
  and Microphone grants; a later press without them opens System Settings
  at the grant's pane. An agent never asks and never opens it. Source ▸
  Microphone Only records a voice-over — the microphone alone, the panel
  staying up with its meter and a Pause button — onto a new back
  Microphone track at the playhead.
- **Timeline** with a frame-accurate ruler, filmstrips and waveforms from a
  per-media cache, three row heights, magnify/⌥-wheel zoom about the cursor,
  and gesture sessions for drag, trim, rate-stretch (⌥ on the end edge),
  slip (⌥⇧ on a body), roll (⌥⇧ on an edge), marquee select, playhead scrub
  (and Space plays and pauses from anywhere but a field being typed into),
  marker drag, audio fade handles and track reorder — each one undo step,
  each snapping to clip edges, markers and the playhead (N toggles, ⌘
  suppresses). Double-clicking an empty span closes that gap; a media row
  dropped with ⌥ inserts and with ⇧⌥ overwrites. Double-clicking a clip
  renames it in place, a labelled clip wears a 6 pt dot in its label's
  colour on its name strip (the tint still says the kind), and a track
  header has eye, speaker, lock and headphones — solo. Right-clicking a
  header or an empty lane opens that track's menu: the four toggles and
  Remove Track.
- **Canvas** with an `AVPlayerLayer` under a transparent overlay: move, scale,
  rotate and crop handles, line/arrow endpoint handles, safe-area guides,
  snapping to the canvas centre and edges, inline text editing (the field
  grows and wraps as you type, as the text will once applied; Return
  applies, ⇧Return starts a new line, and Esc asks before dropping a
  change), a region
  band on Z for a zoom or an obscured area, and Fit / 50 % / 100 % / 200 %
  zoom stops. With an action selected, a drag or an arrow-key nudge edits
  that action's end state, as the inspector does.
- **Inspector** with four tabs — Clip, Media, Document and **Assistant**
  (View ▸ Assistant, ⌃⌘A): a conversation with a built-in assistant that
  edits the window's project with the same tools an agent uses, each call
  its own undo step. It streams its reply and a line per tool call — one
  text you can select and copy across entries — asks before it writes a file
  — naming the file, and saying REPLACES when one is already there — and
  waits for Allow or Deny (a click; Return never answers); the Assistant
  tab's title wears a dot while it waits, whichever tab is showing; Return
  sends and ⇧Return starts a new line, the message field growing to five
  lines; Send becomes Stop while it works, Clear starts over, and a meter
  shows how full the conversation is. It runs on your own Anthropic API key
  and the model you choose (claude-opus-5-5 unless you pick another), both
  set in Settings' Assistant pane; changing either starts a new
  conversation. The same pane sets when a long conversation is compacted
  into a summary (at 300,000 tokens unless you change it, or never) and
  whether Anthropic may clear old tool results from the model's view;
  changing those keeps the conversation going. It will not record the screen
  or send audio to the cloud transcriber (File ▸ Generate Captions… does
  that, with the price in front of you), and each message tells it the
  playhead, the selection and the open nest as they stand when you send.
  Each turn ends with what it cost — Reelcut's own estimate at LiteLLM's
  prices, naming the table's date, and "unknown" rather than $0 when a
  response could not be priced — and every response is one line in
  `spend.jsonl` in Reelcut's Application Support folder (tokens and dollars,
  never your key or the conversation). The tab's Spend row shows what the
  conversation has cost since you last cleared it, and Settings' Assistant
  pane what this calendar month has cost (the month in UTC, as the ledger
  records it), both Reelcut's own estimate: the Anthropic Console is the
  truth for what your account was billed. The Clip tab is a selection header
  — the clip's name, editable there for a single clip and the one place a
  name can be cleared back to what the clip shows, with its label dot — and
  the clip's **action lane**: its actions as numbered bands you click to
  select and drag to move (or drag by an end to resize — on the timeline's
  bands too, one undo step), over the clip's transition, fades and motion
  presets, with Zoom to Region, Zoom Back and Add Action, and the selected
  action's start, length, curve and Remove — pinned above the scroll view
  with a row of sub-tabs the selection's kind earns (Text or Shape, Picture,
  Sound, and Clip for timing, speed, transitions and motion presets; a mint
  `◆N` marks a tab the selected action keys), over that tab's sections, each
  collapsible. Every field shows and writes the clip's base props — or,
  while an action is selected, that action's END state, read at its end
  tick; unchecking a switch there (a shadow, an outline) keys it off at the
  action's end. Each row is marked ◆ (the action keys it), ◇ (another action
  does), ○ (it follows a keyed value) or ⊘ (actions cannot animate it), and
  a slider shows the value at the playhead as a coral tick. A section offers
  Reset only while it differs from its default, and Clear (taking its keys
  out of the selected action) while that action keys it; a keyed row's ◆
  becomes a × on hover, a right-click offers Remove from action, Go to
  action and Reset to default, and an edit the project refuses says why at
  the inspector's foot. Playing or scrubbing INTO an action selects it; esc
  or the lane's Clip chip leaves it, and ⌫ removes it. The timeline draws
  each clip's actions in a lane under its name, the selected one solid mint
  with its span washed down the clip and shaded on the ruler.
- **Editing**: move, nudge, trim, slip, roll, split, delete, lift, ripple
  delete (one range, or many at once), close gap, insert time, insert and
  overwrite, duplicate, speed (×0.1–×1000, or fit to a duration),
  freeze frame, detach audio, transitions,
  actions, markers, tracks, canvas size and rate; a clip's own name and
  colour label (Clip ▸ Rename…, Clip ▸ Label ▸; a clip with no name of
  its own is called what it shows), solo (Track ▸ Solo — the other tracks
  in the same container go quiet, and mute still wins), and Paste
  Attributes (⌥⌘V: the copied clip's look onto the selection, each group
  replaced whole, a text clip keeping its words and a shape its kind and
  size), with Edit ▸ Paste Graphic Properties beside it for what ⌥⌘V
  leaves alone: a copied graphic's properties, its text and colours
  included, onto every selected clip drawn by the same graphic, each
  keeping its own size, in point and length. Every edit is a pure op in the
  Rust core returning a new immutable project handle, so undo is a stack of
  handles and a refused edit costs nothing.
- **The screencast trio.** **Remove Silences** (Clip ▸ Remove Silences…)
  finds the dead air — Judge by Voice or Level, threshold, minimum length
  and padding, over the selected clips or everything audible — shades the
  candidate spans on the ruler and the lanes while you tune it, and takes
  them all out in one undo step, however many cuts that is. **Voice is the
  default**: quiet means "nobody is talking", judged by a Silero
  voice-activity model that runs on your machine over each file once and is
  cached beside the waveform — so a quiet microphone is not mistaken for
  silence and a hum is not mistaken for speech. A clip whose sound holds no
  voice at all (music, a tone) falls back to the level rule and the sheet
  says which files those were. It measures what you HEAR, not what is
  in the file: the level it tests is the waveform peak times the mix
  envelope, so a muted or soloed-out clip is silent for free. **Zoom to
  Region** (Z, or the action lane's zoom button) is the screencast zoom:
  drag a rectangle over the selected clip and release, and the core solves
  for the scale and position that bring it to the canvas — through the
  clip's rotation and crop, eased at both ends, one action, one undo step;
  ⇧ fills the canvas instead of fitting, and Zoom Back animates to where
  the clip started. **Obscure** hides a face or a password field behind up
  to four blurred or pixelated regions per clip, each drawn on the canvas
  or typed into the inspector, each riding with its layer through every
  scale, move and rotation, and each animatable like any other property.
- **Words.** Captions go in and out: File ▸ Import Captions… reads a
  SubRip file, **Generate Captions…** writes one from the clip's own audio —
  **on this Mac** with Apple's own recogniser (a language, a scope, a
  progress bar, no length limit, and a Download button for a language whose
  model this Mac does not have yet) or **with AssemblyAI**
  in the cloud, which knows far more languages and hears them better — and
  **Export Captions…** writes a track back out as `.srt` or `.vtt`. The
  cloud engine sends audio off this machine, so the sheet says so before the
  button does anything: which files would be uploaded, how long they are and
  what they would cost at today's published rate. Your API key goes in
  Reelcut ▸ Settings… (⌘,), under Transcription — a file only you can read, never a launch
  argument — and what comes back is cached in the project package, one
  transcript per media file, re-used by the next run, with the copy at
  AssemblyAI deleted as soon as it has been read. If every requested media
  already has a current readable transcript in the package, Generate Captions
  can reuse the whole batch without an API key or network request. Pending
  remote deletion remains recorded and is reported as deferred; a later run
  with the originating account and region's key retries safe deletion IDs.
  With AssemblyAI's Speakers on, Subtitles put each speaker in their own
  colour — white, yellow, cyan, green.
  Either engine can also make **word captions**, the large one-row style of
  shorts and reels, in one of five styles — Highlight, Pill, Karaoke, Build
  and One Word — where each page is filled to the width it will actually
  MEASURE on your canvas rather than to a word count, the word being said
  lights up as it is said, and a word too wide for the frame shrinks before
  it wraps; generating again with Replace restyles a track in one undo step
  (the sheet's Style popup previews each style on your canvas, and its Replace
  checkbox names the tracks it will replace).
  A caption is an ordinary text clip
  either way, which is what makes burn-in on export free and lets you drag
  one to retime it. Text clips also arrive and leave under their own power:
  a **typewriter**, a **word fade** or a **line rise**, with separate in
  and out durations. The core computes how far along a reveal is, once per
  frame, so the preview, a rendered frame and an export cannot disagree
  about it. Four display faces for word captions ship inside the app under
  the SIL Open Font License, their licences beside them: Montserrat
  ExtraBold, Montserrat Black, Anton and Bebas Neue.
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
  length — a plate of a MOVIE runs its own file's length instead, so the
  footage plays at its own speed. **Clip ▸ Add Blurred Background** is the
  screencast move — the selected clip copied behind itself, blown up to
  fill the canvas and
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
  **ProRes 4444** and **HEVC with alpha** export a real alpha channel, which
  is what a transparent canvas is for — ProRes 4444 as a master for another
  editor, HEVC with alpha (a QuickTime movie) as the small file a web page
  or a player lays over its own background. Set the background's opacity in
  the Document tab and the note there counts the formats that keep it —
  "Transparent — kept by 3 export formats.": ProRes 4444, HEVC with alpha
  and APNG (a GIF can only be transparent or not, with nothing in between).
  **Burn in
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
  player (the plan JSON is compared as a string). VP9 video in an MP4 plays,
  and AV1 too on an M3 or later Mac; a video this Mac cannot decode (AV1 on an
  M1 or M2, VP9 Profile 1 or 3, VP8 in an MP4 or MOV) is refused at import with a sentence
  naming its codec. A WebM or MKV file (VP9, AV1, H.264 or HEVC video with Opus,
  Vorbis or AAC sound) opens with no question: its streams are copied, not re-encoded,
  into a movie in `~/Library/Application Support/Reelcut/Rewrapped/`, after a
  check that the copy fits on the disk. A copy that takes more than a second
  shows its progress in a small window whose Cancel stops it and adds nothing.
  The media keeps the WebM's own name, and a project whose copy is gone copies
  it again from the WebM when it opens. A file the opt-in ffmpeg step converts
  keeps its own name too, and that step copies a constant-rate VP9 stream
  instead of re-encoding it.
- **Export** through an `AVAssetWriter` over the same composition, the
  format (H.264, HEVC, HEVC with alpha, ProRes 422, ProRes 4444, M4A, WAV,
  AIFF, GIF, APNG) and the size chosen separately and both resolved by the core — the default
  size is the document's own, or for a GIF or APNG the format's cap fitted to
  it — and an optional loudness target and timecode burn-in over it, plus an
  offline single-frame render used for verification and by File ▸ Save Frame….
  The size the sheet and the `export` tool report is the size the file has: a
  document with an odd width or height exports one pixel smaller on that edge
  on the formats that need even dimensions (H.264, HEVC, HEVC with alpha,
  ProRes 422), where the Size popup names the row "Document (even)"; ProRes
  4444, GIF and APNG keep the odd edge. A movie whose size is within a pixel
  of the document's shape — that evened size, a custom size in the
  document's proportions with an odd edge (written a pixel smaller, at any
  scale), or a standard size whose long edge rounded — is filled edge to
  edge rather than padded with a black line; any other shape is letterboxed,
  or on ProRes 4444 and HEVC with alpha refused, since padding would destroy
  the alpha channel.
- **Motion graphics.** A graphic clip is drawn every frame by a small
  JavaScript module in the package's `graphics/` folder. A person puts one on
  the timeline from Insert ▸ Graphic — six bundled templates (Bar Chart,
  Callout, Counter, Kinetic Type, Lower Third, Title Card) or a `.js` of
  their own — edits its properties, size and timing in the Clip tab's
  Graphic sub-tab, brings in a font or a picture with File ▸ Add Font to
  Graphics… and Add Image to Graphics…, and reads the API from Help ▸
  Graphics Reference. An agent can do the whole job over MCP: read the
  reference, write a module, look at its frames without placing it, bring in
  a font or a picture, put it on the timeline and change its properties. The
  module's standard library measures a path, finds a point along it and
  draws it on. The
  project keeps the last 10 versions of each graphic's code in
  `graphics/history/`, kept whenever the app sees the code replaced, so an
  agent can restore an earlier version, delete a graphic no clip uses (its
  code is kept and can be restored) and rename one — every clip that uses it
  follows, and Undo renames it back. A person renames, deletes and restores
  from File ▸ Rename Graphic…, Delete Graphic… and Restore Graphic Version…
  (which puts back the newest kept version); each is a small sheet that
  shows Reelcut's reason when it refuses.
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
`archive/reelcut-roadmap-2.md`'s phases 0 through 7 have landed — the
groundwork, the cutting moves, clip identity, the screencast trio, captions
in both directions with the built-in text animations, sound (the mono fold,
a level meter, Normalize Clip, loudness on export and the two uncompressed
audio formats), looks (blend modes, gradient fills, the two background
commands and filters as animation targets), output (Save Frame…, ProRes 4444
with a real alpha channel — HEVC with alpha has joined it since — the
timecode burn-in, remembered and named export settings, and the export
queue), viewing and finding (preview quality, a
second preview window, and a Media tab you can search, sort and filter), and
now the last of them: editing INSIDE a nest, which the spec designed and left
and which every op reaches through one envelope key.
`designs/adr/` holds the condensed record of each road map, and the GitHub
`docs/manual-checks.md` the checks only a person at the machine can make.

What has actually been checked, and what has not: the model, the ops, the
composition plan, the frame recipe, the compositor, save/open and export were
verified by driving the built app over MCP and comparing pixels and probed
files against the sources (spec §10 steps 3, 4, 5, 7, 9, 10, 11 and 12). The
parts only a person can reach — live playback and its 60 fps target (steps 4
and 5), the timeline view (step 6), the canvas overlay (step 8), the
inspector — are written and typecheck but have not been exercised by anyone;
`docs/manual-checks.md` lists them.
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
agent/                the assistant helper: Bun and the Anthropic SDK's Tool Runner,
                      built into Contents/Helpers/reelcut-agent (build.sh)
mcp-proxy/            Rust crate — reelcut-mcp, the stdio MCP server MCP clients start,
                      built into Contents/Helpers/reelcut-mcp
designs/              spec/ — the accepted design and spec, one file per section;
                      adr/ — condensed records
archive/              closed road maps, verbatim (INDEX.md)
project.yml           xcodegen definition — source of truth for the Xcode project
Makefile              Build orchestration
```

### `app/Sources` file map

| File(s) | Owns |
|---|---|
| `ReelCore.swift` · `ReelOps.swift` | the FFI and the op vocabulary: `ReelCore.swift` is the **only** `rc_*` caller (`ReelProject` — handle + lazy snapshot — `ReelTime`, `ReelSnap`, `ReelExport`, and the op-argument types), `ReelOps.swift` holds `ReelOp` and the typed op builders |
| `ProjectSnapshot.swift` | the `Codable` mirror of the §5.2 project JSON, the plan and the recipe, plus the §5.3 placement maths |
| `ProjectDocument.swift` | NSDocument, `.reelcut` package read/write, and the single mutation point (`applyEdit`, the live-edit trio, undo as a handle stack) |
| `MediaImporter.swift` | `AVURLAsset` probing (the one file allowed `async`/`await`), thumbnails, waveform peaks |
| `CompositionBuilder.swift` · `Compositor.swift` · `LayerRenderers.swift` · `LayerRenderersText.swift` · `Playback.swift` · `RecipeSource.swift` | plan → `AVComposition`; the `AVVideoCompositing` Metal pipeline — five states from three fragment functions, one of them reading the destination so a layer can blend; text/shape/image textures, a shape's gradient and the three text reveals the recipe asks for; the player and its rebuild-vs-refresh rule; the registry the compositor reads a recipe from, one slot per document and per export |
| `CaptionImporter.swift` · `CaptionLayout.swift` · `CaptionStyle.swift` · `CaptionPages.swift` · `Transcriber.swift` (+`Extract` `Jobs` `Languages`) · `CaptionExporter.swift` | captions in and out: the SubRip grammar, the placement every producer shares, the five word caption styles and the pager that fills their pages to a measured width, on-device speech recognition and the cue builder over it, the extractor and the job list both engines share, and the `.srt` / `.vtt` writer |
| `CloudTranscriber.swift` (+`Media`) · `MediaTranscript.swift` · `AssemblyAIClient.swift` (+`Session`) · `AssemblyAITranscript.swift` · `AssemblyAIConfiguration.swift` · `AssemblyAILanguages.swift` · `SecretStore.swift` · `CloudProgress.swift` · `CloudEstimate.swift` | captions from the cloud (road map 6): the run that groups clips by media and deletes what it fetched, the transcript cache in the package, AssemblyAI's five REST calls and their wire values, where the client speaks and what it says it is, the `0600` key file, the progress number and the price the sheet shows before the button |
| `Exporter.swift` · `ExporterSettings.swift` · `ExporterWriter.swift` · `ExporterWriter+Settings.swift` · `ExporterAudioGain.swift` · `ExportSheetController.swift` (with `ExportSheetOptions` `ExportSheetResolve` `ExportSheetPresets` `ExportProgressSheetController`) | writing a file — two passes wherever it holds sound, the first measuring loudness — and rendering one frame offline; the settings each row becomes in AVFoundation's terms, and the loudness gain applied to the float mix and quantised once; the sheet's controls, the resolution behind them and the progress sheet |
| `FrameWriter.swift` · `EditorViewController+SaveFrame.swift` | one composed frame to a PNG, JPEG or HEIC — a value type with no AppKit in it, called by File ▸ Save Frame… and by `render_frame` alike — and the panel that picks the URL |
| `ExportPresetsStore.swift` · `ExportQueueController.swift` · `ExportQueueWindowController.swift` · `AppSupport.swift` | the last export choice and the named presets as a value, the queue (one job at a time, each holding the timeline as it was enqueued) and its window, and the one spelling of `~/Library/Application Support/Reelcut/` |
| `AudioTap.swift` · `AudioDSP.swift` · `LevelMeter.swift` · `LevelMeterView.swift` | the sample-level audio the plan cannot carry (noise reduction, the compressor, the mono fold, the pan) and the level meter's model and its one view |
| `MediaPeaks.swift` · `AudioNormalize.swift` · `SilenceDetector.swift` (+`Walls`) · `SileroVAD.swift` · `MediaSpeech.swift` | the waveform cache and the questions asked of it: a clip's own peak (Normalize) and peak × envelope (the quiet spans in Level mode) — plus the Core ML voice model and its own per-media cache, which is what Voice mode asks |
| `Loudness.swift` | BS.1770-4 integrated loudness and true peak, and the export gain that follows |
| `TimelineLayout.swift` · `TimelineSessions.swift` · `TimelineView.swift` | all tick↔point arithmetic; the gesture session structs; the timeline view |
| `CanvasSessions.swift` · `PreviewCanvasView.swift` · `EditorViewController+PreviewQuality.swift` · `PreviewWindowController.swift` | canvas geometry and gestures; the preview and its overlay; the preview's render size (View ▸ Preview Quality, applied to a copy of the player's composition so the export path cannot see it) and the second preview window, an `NSPanel` carrying a second layer on the same player |
| `InspectorPane.swift` · `InspectorTab.swift` · `InspectorViewController.swift` · `ClipPane` `MediaPane` `DocumentPane` `AssistantPane` (with `VideoPane` `AudioPane` `TextPane` `ShapePane` as section factories) | the binding that knows about actions, the four tabs, one file per tab, and the sections the Clip tab composes |
| `MediaRowView.swift` · `MediaListFilter.swift` · `MediaPaneCommands.swift` · `MediaUsage.swift` · `MediaReveal.swift` | the Media tab around its pane: the row and the drag it sources, the find band as a value, the row's commands, the one answer to "is this file used" (which walks the nests), and Reveal in Timeline |
| `EditorViewController.swift` + `EditorViewController+{Timeline,Canvas,Inspector,Export}.swift` | wiring in the base file, features in extensions |
| `AgentServer.swift` + `AgentServer+{Arguments,Gate,Parity,Project,Clips,Tracks,Media,Render,History,Silence,Captions,CloudCaptions,Audio,Background,Transitions,Scope,Recording,RecordingArguments,RecordingResult,Graphics,GraphicImports,GraphicRender,DevTools}.swift` · `AgentCatalog.swift` + `AgentCatalog+{Clips,Files,Captions,Audio,Transitions,Graphics,Declarations}.swift` | the MCP endpoint, its handlers, and the tool catalog |
| `AgentLane.swift` · `AssistantToolTable.swift` · `AssistantSession.swift` · `AssistantConfiguration.swift` · `AssistantPrompt.swift` · `AssistantLiveContext.swift` · `AssistantSpend.swift` | the one door every tool call goes through (a lock, one call at a time, and the wait for mouse-up), and the table of tools the assistant may not call or must ask about first; the assistant's per-window session over the bundled helper, its key, base URL and model, its core tools and prompt texts, the live context each message carries, and what each response cost (the spend ledger, the price cache's place, the turn's cost line) |
| `AssistantView.swift` · `AssistantTranscriptView.swift` · `AssistantComposer.swift` · `AssistantTranscript.swift` · `AssistantContextMeter.swift` · `AssistantSettingsPane.swift` · `EditorViewController+Assistant.swift` | the Assistant tab's views, which hold no conversation; the multi-line message field, with its own undo; the transcript the window keeps; the context meter; Settings' Assistant pane (key, model and chat settings); and the glue between the tab and the window's session |
| `RecordingSetup.swift` · `ScreenRecorder.swift` (with `+Finishing` and `+Content`) · `RecordingLanding.swift` · `ProjectDocument+Recording.swift` · `RecorderPanelController.swift` (with `+Rows` and `+Recording`) · `RecorderStatusItem.swift` · `AppDelegate+Recording.swift` · `AgentServer+Recording.swift` | screen recording (road map 3): the values, the session over ScreenCaptureKit and a second `AVCaptureSession` for the microphone, the landing as ordinary media, the floating non-activating panel with its countdown and meter, the menu-bar status item, and the `record_screen` tool |
| `AppDelegate.swift` · `EditorWindowController.swift` · `WelcomeWindowController.swift` · `main.swift` | menus (nil-target selectors), window, welcome |
| `SpeedSheetController.swift` · `RelinkSheetController.swift` · `SilenceSheetController.swift` (with `SilenceDetector.swift` behind it) · `TranscribeSheetController.swift` (+`Cloud` `Commit`) · `SettingsWindowController.swift` · `MCPSettingsPane.swift` | the remaining dialogs, and Reelcut ▸ Settings… (with its MCP section) |
| `Theme.swift` · `Controls.swift` · `OptionControls.swift` · `Sheets.swift` · `EditorChrome.swift` · `FileDropView.swift` | shared chrome, copied from Rasterize |

## Building

Requires Xcode 26 or later (the macOS 26 SDK), Rust (cargo), [xcodegen](https://github.com/yonaskolb/XcodeGen), and [bun](https://bun.sh) (the assistant helper, `agent/`, is built by every `make app`, typechecked by `make typecheck` and its price function tested by `make test`; without bun they fail rather than skip).

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make dist       # make app, then the Distribution build (no dev tools; the assistant helper signed with the hardened runtime) → build/Build/Products/Distribution/Reelcut.app, checked
make run        # build and launch
make test       # Rust core, graphics and MCP proxy tests, then the agent lane's proof (tools/proof/assistant_lane_proof.py), the prompt texts' checks (tools/proof/assistant_prompt_proof.py --probe), the price function in both readers (tools/proof/prices_proof.py, no network) and the proofs' ledger and monthly budgets (tools/proof/budget_proof.py, no network)
make lint       # cargo clippy --all-targets -D warnings
make typecheck  # swiftc -typecheck of app/Sources — the ONLY authoritative Swift check, then agent/'s tsc --noEmit (through bun)
make project    # xcodegen generate
make prices     # regenerate agent/prices/anthropic.json from LiteLLM's price table (network); the file's only writer
```

`Reelcut.xcodeproj` is generated — run `xcodegen generate` (or `make project`)
after editing `project.yml`, and don't commit the project file.

## AI agent access (MCP)

Reelcut serves an MCP server (streamable HTTP) on a Unix socket it binds at
every launch, `~/Library/Application Support/Reelcut/Agent/agent.sock`. An MCP
client reaches it through `reelcut-mcp`, the stdio helper inside the bundle,
which lists the tools without opening Reelcut and launches it in the
background on the first tool call that finds it not running.

**Reelcut ▸ Settings… ▸ MCP — Copy MCP Command** puts the line that registers
the helper with Claude Code on the clipboard, with the path of the bundle you
ran it from; the section also shows the helper's path:

```sh
claude mcp add --scope user reelcut -- '/Applications/Reelcut.app/Contents/Helpers/reelcut-mcp'
```

Claude Desktop takes the same helper in its `claude_desktop_config.json`:

```json
{"mcpServers":{"reelcut":{"command":"/Applications/Reelcut.app/Contents/Helpers/reelcut-mcp"}}}
```

The socket is yours alone: its folder is `0700` and the socket `0600`, so
only processes running as you can connect — and any of them can, while the
app runs.

To drive a build for verification, give it a socket of its own with
`RC_AGENT_SOCKET`, so it never touches your own, and
point `tools/proof/mcp.py`'s `MCP` or `reelcut-mcp` (with the same variable
set) at that path:

```sh
make app
d="$(mktemp -d)"; echo "$d"
(RC_AGENT_SOCKET="$d/agent.sock" build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut \
   -ApplePersistenceIgnoreState YES > "$d/reelcut.log" 2>&1 &)
```

Calls run one at a time. A call made while you are dragging something in
the window (a clip, a canvas handle, an inspector slider) waits for mouse-up
and then runs, as its own undo step after the drag's.

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
| `new_project {path?}` | a blank 1920×1080 / 30 fps project, saved straight away when given a path; a path another open project has is refused, and nothing is created |
| `save_project {path?}` | returns once the package is really on disk; a path another open project has is refused |
| `close_project {discard?}` | closes a project and its window (File ▸ Close, ⌘W). Unsaved changes are refused unless `discard: true`, and so is a window with a sheet open; it writes nothing |
| `get_project` | the whole §5.2 JSON, plus the playhead, selection and in/out range that live only in the app |
| `import_media {path}` | probes a file and returns the **new media id**; `add_clip` then places it |
| `import_captions {path, track?}` | an SRT file as text clips (File ▸ Import Captions…) |
| `consolidate_media {}` | copies every referenced file into the package (File ▸ Consolidate Media…) |
| `record_screen {seconds, source?, display?, window?, microphone?, system_audio?, show_clicks?, include_reelcut_windows?, rate?, size?, place?, path?}` | records a display (index, 0 = main) or a window (a `CGWindowID`) for `seconds` and lands it as a clip at the target document's playhead — or as an untitled document rated at `rate` when nothing is open (File ▸ New Recording…). `microphone` records the default microphone to a second file on a Microphone track; `path` is a FOLDER override; `include_reelcut_windows` puts Reelcut's own windows in a display recording, which leaves them out by default. `source: "voice_over"` records the default microphone alone (the panel's Microphone Only) onto a new back Microphone track, reading only the Microphone grant. It reads the grants and never asks: the refusal names the System Settings pane, and a shell-launched instance runs under its TERMINAL's grants |
| `transcribe {clips?, language?, place?, engine?, speakers?, vocabulary?, refresh?, style?, replace?}` | speech recognition into caption clips (File ▸ Generate Captions…). Returns the cues in ticks whether or not it places them, and `place: false` changes nothing at all. `style` is `subtitles` (the default) or a word caption style — `highlight`, `pill`, `karaoke`, `build`, `one_word` — whose pages are filled to a measured width and whose cues carry their `words`; `replace: true` swaps out the caption tracks it would have made over the same clips in the same undo step and lists them under `replaced`. `engine` is `apple` (the default, on this Mac, nothing uploaded) or `assemblyai` (the whole audio of each media file goes to AssemblyAI and is billed; the transcript is cached in the package and deleted at the far end). The on-device engine needs no grant and has no length limit; a language whose model is not installed on this Mac is refused by name and never downloaded by the tool — a person installs it from the sheet's Download row. `speakers`, `vocabulary` and `refresh` apply only to the cloud engine and are refused by name without it; with `speakers` and `subtitles`, each speaker's cues take their own colour |
| `export_captions {track?, path, format?}` | one text track out as `.srt` or `.vtt` (File ▸ Export Captions…). The track is never guessed — with no all-text track, or more than one, it refuses and lists the candidates. A trailing `.srt` or `.vtt` in `path` becomes the format's own; any other extension is kept, as the save panel keeps it (`chart.png` → `chart.png.srt`) |
| `detect_silence {clips?, mode?, voice_confidence?, threshold_db?, min_length?, padding?}` | the quiet spans of the timeline, which `ripple_delete_ranges` then cuts — the same detector Clip ▸ Remove Silences… uses, so an agent and the sheet propose the same cuts. It changes nothing. `mode` is `voice` (the default, the cached Silero probability against `voice_confidence`) or `level`; either way a moment the mix envelope alone puts under `threshold_db` is quiet, so mute and solo are already in the answer, and the result names any file still being analysed and any clip judged by level |
| `normalize_clip {clips, peak_db?}` | sets each clip's volume so its own loudest moment lands at `peak_db` (default −1 dBFS) — the Volume section's Normalize button and Clip ▸ Normalize. Measured from the waveform cache over the part that plays, so it knows nothing about the volume, fades, ducking, mute or solo already on the clip; it replaces the volume rather than multiplying it, writes the clip's base level even inside an action, and leaves `muted` alone. One gain per clip, one undo step, and what it could not measure comes back under `skipped` |
| `set_playhead {t}` | moves the playhead and seeks the preview |
| `set_range {start?, end?}` | the in/out range (I / O / ⌥X); no bounds clears it |
| `set_selection {clips?}` | the timeline selection (a click); no clips clears it |
| `set_scope {nest?, clip?}` | opens a nest to look and edit inside it — the mirror of double-clicking a nest clip and of Clip ▸ Open Nest (⌘↓). At most one argument, and NEITHER means the timeline: send it with no arguments to come back out. `clip` is the precise spelling, since one nest can be shown by two clips at two different starts. With a nest open `get_project` lists ITS clips, `render_frame` draws it at its own frozen size, and every op lands inside it — the same view a person gets. Every op tool also takes `scope` directly, which names a nest for one call and outranks whatever is open |
| `undo` · `redo` | one step each (⌘Z / ⇧⌘Z), reporting the step's name |
| `render_frame {t, max_width?, path?, format?, burn_in_timecode?}` | **the verification hook**. With neither `path` nor `format` it writes a PNG to a temporary file, exactly the call it always was. `format` is `png`, `jpeg` or `heic` and WINS over the path's extension, which is replaced rather than appended to (`{path: "shot.jpg", format: "png"}` writes `shot.png`); `png` and `heic` keep the canvas's alpha and `jpeg` flattens onto black. It is the same writer File ▸ Save Frame… uses, so a still from the menu and one from here are byte-identical. `burn_in_timecode` draws the document's timecode over the picture — the only way a burn-in can be photographed |
| `export {preset, path, size?, range?, video_bitrate?, audio_bitrate?, loudness_lufs?, peak_dbtp?, burn_in_timecode?}` | writes a file and waits for it; `preset` is the encoding, `size` a Size-popup row (`document`, `1080p`, …) or `[width, height]`, default the document's size (a GIF or APNG's cap); `range: "in_out"` scopes it to the in/out range; the bitrates are the sheet's Quality popup in bits per second; `loudness_lufs` normalises the whole mix by one gain to that integrated target and `peak_dbtp` is the ceiling that gain is capped against (a ceiling with no target is refused — there would be nothing to cap). `burn_in_timecode` draws the document's own timecode over every frame (the export sheet's checkbox), showing PROJECT time even in a file written from the in/out range. The result reports what the file's sound MEASURED, asked for or not, and echoes the burn-in either way; the result's width and height are the file's |
| `graphic_reference` · `write_graphic {name, source}` · `get_graphic {name?}` · `render_graphic {name, frames?, frame?, props?, width?, height?, max_width?, background?, format?, path?}` · `import_graphic_font {path}` · `import_graphic_asset {path, name?}` · `delete_graphic {name}` · `rename_graphic {name, to}` · `restore_graphic {name, revision?}` | the nine graphics tools, the agent's whole loop for a motion graphic: read the API once, write `graphics/<name>.js` and read its compile back (`ok` and `diagnostics`, not an error), look at up to 16 of its frames as a contact sheet with no clip (or one frame's SVG), copy a `.ttf`/`.otf` into `graphics/fonts/` — its reply names the exact family names the engine reads — or a picture into `graphics/assets/`; then `add_graphic_clip` and `set_graphic` place and change it. File writes are not undoable, but the text a write replaces is kept (the last 10 per module; `kept` lists them, and `get_graphic {}`'s `history` lists deleted modules too) and `restore_graphic` brings one back; `delete_graphic` is refused while a clip draws the module and keeps the deleted text; `rename_graphic` moves the file, its kept texts and every clip that names it as one undo step, and undo renames the file back. The first six mirror the Graphic sub-tab, Insert ▸ Graphic (`write_graphic` then `add_graphic_clip`), File ▸ Add Font to Graphics… and Add Image to Graphics…, and Help ▸ Graphics Reference; the last three mirror File ▸ Delete Graphic…, Rename Graphic… and Restore Graphic Version… (which restores the newest kept text) |

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
  the composition plan and the per-frame recipe, and reads a WebM or Matroska
  file's index for the import's copy; the platform decodes, composites and
  encodes.
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
