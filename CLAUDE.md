# CLAUDE.md

Reelcut — a screencast-style video editor for macOS: a Swift/AppKit UI over a
Rust staticlib core, the same shape as `~/devel/rasterize`.

**It builds and runs.** M1 (Cut) is done and verified against spec §10; most
of M2 landed with it.

Nine things in `designs/`, and you want all of them:

- **`designs/reelcut-remaining.md` — what is LEFT, and the record of the
  debt that was paid. START HERE if you are picking up new work.** Road map
  2 is complete, and the debt two large phases left behind is now CLOSED and
  written up there: §1 (two fixes whose proof instruments were untracked —
  the only place the project's own standard was not met) and §2 (two live
  defects, one of which became the cache completion marker). What is still
  open is §3, the size ledger a feature phase consults before it pays its
  toll, §4, the checks only a person at the machine can make, and §5, where
  a third road map would start.
- **`designs/reelcut-roadmap-3.md` — road map 3, BUILT: screen recording**,
  the first item taken off road map 2 §4. It records the decision that
  reverses spec §1's non-goal, the spike (R0) whose seven answers were
  pasted into it before any code — two of which overturned the plan — the
  two phases (R1: no op, no schema change, one tool, three size tolls; R2:
  pause and resume from the menu bar, and the panel that goes away — no
  op, no tool, no FFI change, a seventh spike answer, five files), each
  phase's adversarial review and fix wave, and what only a person at the
  machine can still check. START THERE if you are touching the recorder.
- **`designs/reelcut-roadmap-4.md` — road map 4, DESIGNED and not built:
  Remove Silences, second pass.** A spike (S0, run 2026-09-13, its three
  instruments tracked in `tools/proof/silence_spike/`) measured the shipped
  −40 dBFS level rule marking nine tenths of the recorder's own microphone
  file silent and finding nothing under a hum, tried Apple's
  `SpeechDetector` (reports nothing), the transcriber's word ranges (absorb
  the pause before a word), SoundAnalysis (edges a quarter second outward)
  and Silero VAD v6.2.1 through Core ML (edges within a frame, 350×
  realtime, 640 KB, MIT, no new runtime, no `async`, no grant) — and the
  plan (S1) is a per-media `cache/speech/` beside the peaks and a `mode`
  on the detector, voice by default with level as the fallback. START THERE
  if you are touching Remove Silences or `detect_silence`.
- **`designs/reelcut-roadmap-5.md` — road map 5, PLANNED and not built:
  transitions and motion.** Two phases in build detail. E1: three wipe
  directions, eased transitions, a constant-power audio crossfade minted on
  new transitions, `add_transition` at a hard cut from handles and
  `set_transition_style` (schema v7, `OP_NAMES` 57, catalog 77). E2:
  `video.motion` In / Out / During presets the core turns into placement at
  render time, relative and composing (schema v8, no op). Five spec §11
  entries to record first (R5-1…R5-5), tolls, lanes with their files, seams,
  proofs and mutants. Road map 4's S1 must be committed before it starts.
  START THERE if you are touching transitions or adding motion.
- `designs/reelcut-effects-survey.md` — the survey road map 5 came from:
  `~/devel/Concat`'s transitions, effects and filters compared with
  Reelcut's (Concat is AGPL-3.0 — its behaviour was studied, and none of its
  code, shaders, chains or colour tables may be carried over), nine phases
  designed, two spikes measured (`tools/proof/effects_spike/`: offline voice
  rendering through Apple's audio units, Vision person segmentation) and a
  two-reader review. **E3–E9 — tone, filters, looks, adjustment clips, LUT
  import, voice effects, background removal — are DEFERRED** by the user
  (2026-09-15: colour grading and LUT import "eventually, but not now").
  Read it before planning any of them.
- `designs/reelcut-design.md` — the normative spec. The schemas (§5), the op
  table (§6) and the architecture (§7) govern any change to either side; §11
  holds decisions already made, which are not to be re-litigated.
- `designs/reelcut-roadmap.md` — the record of M1–M3: what proved each
  piece, what still needs a person at the machine, and the known limits.
- **`designs/reelcut-roadmap-2.md` — the record of ten phases, ALL NOW DONE**
  (cutting moves, clip identity, the screencast trio, captions and text
  animations, sound, looks, output, viewing, and entering a nest), each
  naming its ops, schema bump, files, MCP mirrors, the proof that closed it,
  and — written after the fact — where its own plan could not be built as
  specified. Its §1 table carries every commit; its §4 is what was
  deliberately left out, which is where a third road map would start.
- `designs/design_handoff_reelcut/` — the chrome cleanup and the identity,
  now SHIPPED. Its `README.md` is the normative source for the redesign's
  metrics (spec §3–§4.4 summarises them); the two `.dc.html` files are
  browser prototypes, not code to port, and `logo/` is the identity master.

## Commands

```sh
make app        # cargo build --release + xcodegen + xcodebuild → build/Build/Products/Release/Reelcut.app
make test       # cd core && cargo test --release  (494 black-box tests)
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
  src/                 model(+_query/_props/_regions/_text) time edit(+_clip/
                       _edge/_insert/_props/_track/_time/_paste/_nest/_action/
                       _zoom/_background) props_check actions transition
                       evaluate recipe(+_text) nest audio snap format
                       export(+_size/_overrides/_table) agent ffi*
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
  `core/src/edit.rs`; `ReelOps.swift`'s typed builders and
  `AgentCatalog.swift`'s tools both mirror it, and spec §6 mirrors it again —
  change one, change all four.
- **Every edit is pure and returns `Option`** (identity or a documented
  refusal = `None`, no undo step). `ProjectDocument` is the single mutation
  point and undo is its stack of handles.
- **Every user-visible edit gets an MCP mirror** (spec §7.9): a handler, a
  catalog entry, and a comment naming the UI path. The startup parity check
  in `AgentServer.start()` has FOUR parts: catalog names against handler
  names, every op in the core's table against the tools (read through
  `rc_op_names`, with an explicit allow-list for ops that deliberately have
  none), each tool's schema shape, and — since road map 2's phase 9 — that
  every op tool's schema declares `scope`, which is the only mechanism in the
  tree that would catch the 56th op somebody adds without one. It cannot see
  argument TYPES — the throwing helpers in `AgentServer+Arguments.swift` are
  the guard for those, `patchArg` included: a value a patch could not read is
  refused by name, never dropped.

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
`http://127.0.0.1:<port>/mcp` — 75 tools: one per §6 op (55, each of which
also takes the `scope` envelope key since road map 2's phase 9) plus the
twenty app-state tools: `open_project`, `new_project`, `save_project`,
`get_project`, `import_media`, `import_captions`, `export_captions`,
`transcribe`, `consolidate_media`, `detect_silence`, `normalize_clip`,
`set_playhead`, `set_range`, `set_selection`, `set_scope`, `undo`, `redo`,
`render_frame`, `export` and — road map 3 — `record_screen`.
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
`tools/proof/phase2_chrome.py`, `phase3_chrome.py`, `phase4_chrome.py`,
`phase5_chrome.py` and `phase6_chrome.py` are the proofs built on it: a
pixel diff of two renders, measured against rectangles from the layout
constants. `expandSections` is what lets one photograph a section built
`defaultExpanded: false` — phase 4's Animation section is the second to
need it — and the fact that it was already there is worth saying, because a
proof that quietly grows its own instrument is not a proof.

**The second form photographs nothing**, and it is here for the reason to
remember when the next piece of app arithmetic has no caller a script can
reach. `CaptionCues` — the four rules that turn recognised words into cues
(phase 4a) — is Swift, and in the app nothing reaches it until a recogniser
has produced words, which needs a grant. The harness links `app/Sources`
from outside the app — at the time the only thing in the tree that did — so
it grew a mode that runs the builder over a word list from a file and
writes the cues as JSON, and `phase4_chrome.py`'s section 8 asserts the
four rules over its answer at their boundaries. The mode was ADDED beside
the render arguments rather than folded into them, so every earlier chrome
script's argument positions still hold.

Two later scripts took the same route rather than photographing something
they cannot: `phase5_chrome.py` compiles a probe out of `Loudness.swift`
alone, and **`phase6_chrome.py` compiles one out of the WHOLE of
`app/Sources`** — a fifty-line `main.swift` over `harness/build.sh`'s own
`swiftc` line — because a menu lives in `NSApp.mainMenu` and is never drawn
into a window, so no render at any size can show a Clip-menu item or the
answer `validateUserInterfaceItem` gives for it. Both cache on modification
times the way the harness does, and a probe that will not build is a scored
FAILURE rather than an exit, so a rotted instrument cannot take the rest of
the score down with it. **When the thing to check is app ARITHMETIC or app
STRUCTURE with no caller a script can reach, the answer is a probe against
`app/Sources` and not a photograph.** Two more took the route after the road
map closed, and one of them PHOTOGRAPHS: `phase9_chrome.py` builds a bare
`TimelineView`, scrolls it and captures through the same `cacheDisplay`
path, because the breadcrumb's corner is only wrong at a non-zero vertical
scroll and every harness render is at scroll 0; `remaining_probe.py` runs
the naming helpers over tables, counts a notification to see the cache
ledger, and renders a filmstrip tile red-then-blue to see the timeline drop
a replaced strip's decoded tiles. A probe can render; what it cannot do is
put up a sheet or a save panel, which is where the structural reads come in.

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
  **The schema is version 6** (`RC_FORMAT_VERSION` in `core/src/format.rs`
  and the header). Version 2 was M3's: filters, reflection, spotlight,
  `Source::Media.reversed`, audio pan / compressor / noise reduction, and
  `Project.nests` all persist, and a version-1 file still opens — including
  the one shape serde cannot absorb with a default, a v1 nest clip whose
  `project` was a path string, which `migrate_1_to_2` rewrites into a named
  empty `Nest`. Version 3 is road map 2's phase 2 — a clip's `name` and
  `label`, a track's `solo` — and has no migrate step, since all three
  default (`format.rs` says why it bumps anyway); version 4 is phase 3's
  `video.obscure`, version 5 phase 4's `text.animation` and version 6
  phase 6's `video.blend` and `shape.gradient`, all on the same terms.
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
  split/join). ⌘G / ⇧⌘G are `EditorViewController+Nest.swift`.
  **You CAN edit inside a nest, since road map 2's phase 9** — this
  paragraph used to say you could not, and the sentence is kept in the
  negative here because it names the block that was removed. The block was in
  the core: every `clip` argument in the op table resolves through
  `Project::clip`, which searches `self.clips` only, so no op could name a
  nested clip. `Project::clip` STILL searches only that, and still means what
  it always did — phase 9's answer was not to teach 55 ops about nests but to
  give the op a SCOPE, which builds a view project in which the nest's clips
  ARE the top level (`core/src/scope.rs`). The round trip (⇧⌘G, edit, ⌘G) is
  still available and still costs the nest clip's own group-level
  properties; spec §4.4 now records what exists rather than what waited.
  **Reverse is in** (`ReverseRenderer.swift`): `Source::Media.reversed` is
  resolved to `cache/reversed/<media id>-<digest>.mov` inside the package,
  rendered on demand behind a progress sheet, substituted per CLIP by
  `CompositionBuilder` (a boomerang is one media, two clips), slated while
  pending. The three audio DSP fields **have both halves** now — the Audio
  pane writes them and `AudioTap.swift`/`AudioDSP.swift` run them through an
  `MTAudioProcessingTap` on the mix, which playback and export share. Pan is
  a constant-power law normalised to unity at centre (so 0 is an exact
  bypass), and noise reduction delays its track by 512 samples.
  Nothing on this list is open any more, and the LAST entry was never open:
  **filters as animatable action targets** were routed by M3 itself and
  bounded by `structural` in phase 3, so road map 2's phase 6 found 6d
  already shipped and spent that budget on proof and two residual defects
  instead. That is what a stale "not started" line costs — it is what made
  the road map plan the same work twice. (`AudioProps.mono` was the other
  entry until road map 2's phase 5a folded it in the tap; the sentence
  that used to stand here — "turning it on would change how existing
  projects sound" — is true and is the feature, since only a project that
  had deliberately asked for mono changes at all.)
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
  **`text.animation`** (`core/src/model_text.rs` since phase 6) is `null` or
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
- **Road map 2, phase 5 — Sound: done.** No schema change (version 5
  stands, and `mono` had been in the file since M1), NO new op (`OP_NAMES`
  is still 53), one new tool (the catalog is **71**), two new export preset
  rows and two new export overrides.
  **`AudioProps.mono` finally does something.** The fold is at the head of
  the tap's Mix stage — after the noise reducer and the compressor, BEFORE
  the pan — and the order is forced rather than chosen: after a pan the
  fold is algebraically self-cancelling (`(g_L·x + g_R·x)/2 =
  ((g_L+g_R)/2)·x`), so the pan would silently degrade into a gain change
  and read as broken. It averages EVERY channel into all of them with an
  early return below two, the guard the pan already uses, because the tap
  is handed the composition track's channel count and folding 0 and 1 of a
  5.1 source would leave four untouched. Two documents were half-true until
  this landed and now say so: a pan on a mono-folded clip is a TRUE pan
  rather than a balance (spec §4.3), and spec §7.2's old sentence — `mono`
  as "a per-segment flag Swift applies with
  `AVMutableAudioMixInputParameters` where possible" — described something
  that API cannot do, since it applies gain over time and cannot combine
  channels. `mono` rides `AudioClipDSP` beside pan, the compressor and
  noise reduction, keyed by clip id, and `Playback` already treats a
  different `audioDSP` as structural, so the rebuild came free. A track
  whose clips do not ask for mono is bit-identical, which is what makes the
  feature safe to ship into projects that already exist.
  **The level meter is the phase's headline deviation, and the road map's
  design for it cannot be built.** It asks for "a second, read-only
  `MTAudioProcessingTap` … `kMTAudioProcessingTapCreationFlag_PostEffects`".
  There is no such thing: `AVMutableAudioMixInputParameters` has exactly ONE
  `audioTapProcessor`, and `MTAudioProcessingTap.h` requires the PreEffects
  or the PostEffects flag but not both — so a track already carrying the DSP
  tap cannot carry a second one, and moving the DSP tap to PostEffects would
  put the compressor behind the fader and change how every existing project
  with a compressor sounds. **So the meter reads the tap that already exists
  and multiplies by the plan's envelope** (`LevelMeter.swift`,
  `LevelMeterView.swift`): the tap is PreEffects and sees the samples before
  volume, fades and ducking, and the envelope at that tick is exactly what
  `CompositionBuilder` hands AVFoundation as volume ramps, so the number is
  COMPUTED rather than observed and is exact rather than approximate.
  `SilenceDetector` had already established the rule — a peak is pre-fader,
  so the level you want is peak × envelope. Do not "fix" it back toward a
  second tap. Around that: metering is a PLAYBACK build alone
  (`CompositionBuilder.build`'s `metering`, passed true by
  `Playback.startRebuild` and nothing else, so every export keeps the audio
  path it had and a metering build taps EVERY audio track, inert ones
  included); the push is a 30 Hz run-loop `Timer` armed and disarmed by the
  rate KVO, not the periodic time observer, which fires only while time
  moves and would freeze a meter at its last lit value instead of letting it
  fall; the MODEL publishes a raw per-channel peak and RMS and the VIEW owns
  the ballistics, which is what lets the proof assert on a number rather
  than a photograph; and the view sits in the flexible gap immediately LEFT
  of the zoom cluster with no divider, because the row's fixed content is
  880 pt against a 900 pt minimum window and a divider's second gap plus its
  hairline would make 905. Starved below 40 pt it draws nothing, the
  selection block's own rule. Three tokens (`DS.meterFill` = the clip
  palette's audio green, `DS.meterTrough`, `DS.meterClip` = the one place
  the bar spends coral). And it is **the app's first
  `import Synchronization`** — two relaxed atomic words, because
  `LevelMeterSink.publish` runs on AVPlayer's render thread where a lock
  invites priority inversion and `main.async` allocates; that is confined to
  `LevelMeter.swift` and is an exception of the same class as `async` being
  confined to `MediaImporter.swift` (app/CLAUDE.md keeps them together).
  **Normalise Clip** is `AudioNormalize.swift`, a value type — peaks in, ops
  out, `CaptionLayout`'s shape applied to sound — so the Audio pane's button
  and the `normalize_clip` tool provably do the same thing; and
  `MediaPeaks.swift` is the shared arithmetic under it, the four pieces
  `SilenceDetector` used to keep privately (the bucket size, the
  project→source mapping through the plan segment's own resolved rate, the
  floor, and the reversed MIRROR about the media's model duration — nothing
  ever generates peaks for `cache/reversed/…`). It REPLACES `volume` rather
  than multiplying it, so a second press is a no-op and comes back as "made
  no change"; it always writes BASE props even inside an action; it leaves
  `muted` alone; each clip of a selection gets its OWN gain; and the window
  comes from the PLAN segment, where "there is no audio segment for this
  clip" is the ONE test that correctly refuses no media, missing media, no
  audio track, `enabled.audio` off anywhere, a still and a nested clip. The
  4× ceiling stands, so a clip under about −13 dBFS is normalised as loud as
  it goes and the result says where it landed. Reachable from the Audio
  section's button and Clip ▸ Normalize, no key equivalent.
  **Loudness on export** is `Loudness.swift` (BS.1770-4: two K-weighting
  biquads run continuously, 400 ms blocks at 75 % overlap, the −70 LUFS
  absolute and −10 LU relative gates, true peak through the standard's
  4-phase 12-tap FIR), and it has no AVFoundation in it, which is what lets
  it be checked against synthesized tones with no fixture file. An export is
  **two passes wherever the file holds sound**, normalised or not: the
  measurement builds its OWN composition (an `AVAudioMix` copy shares the
  tap, and a tap carries per-instance state), reads 32-bit FLOAT so a mix
  over full scale is measured honestly — with `canAdd` MEASURING the request
  and a 16-bit fallback recorded rather than discovered, though on macOS
  26.5.1 float is accepted — and the write pass applies the gain to the
  decoded Int16 samples, rounding and saturating, never truncating. With
  Loudness off the gain path is not entered at all, so an unnormalised
  export is byte-identical to a pre-phase one BY CONSTRUCTION. The sheet
  gains ONE row (Off / −14 / −16 / −23 / Custom, with the −1 dBTP ceiling
  fixed and stated in the hint), the progress sheet says "Measuring
  loudness…" through pass 1, and every export's last line and the `export`
  tool's result both report what the file actually holds. **The limit worth
  knowing before you chase it**: the measurement is float and honest about a
  hot mix, but the write pass decodes to Int16, which saturates BEFORE the
  gain — so a mix that clips is measured correctly, normalised down, and
  still clipped. The gain cannot undo the decode.
  **WAV and AIFF** are two rows beside `audio_m4a`, 16-bit LPCM at 48 kHz
  (24-bit deliberately deferred: it would mean widening the decode settings
  every other preset's encoder consumes, and a silent format mismatch there
  is a file of noise rather than an error). Both carry a NON-NULL
  `avf_preset` — `audio_m4a`'s, because a null one is the ImageIO writer's
  cue and would hand a WAV to `ImageSequenceWriter` — so the field now means
  only "AVFoundation can write this row", which the header, spec §7.8 and
  `core/CLAUDE.md` all say. `export.rs` gave something up before it took
  this on: `describe`, the overrides object and the per-type readers went to
  a new `core/src/export_overrides.rs` (266), re-exported so the five
  modules naming `crate::export::describe` were untouched, and `export.rs`
  came back to 579 with the phase's additions already in it.
  Measured: `make test` **368** (358 before — ten in `core/tests/export.rs`,
  which went 20 → 30; `export_size.rs` grew the two rows and no test),
  `make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors and
  the same 4 AVFoundation warnings, `make app` building, the catalog at
  **71 tools** and the startup parity log EMPTY, and phases 1–4 still
  proving at 66/66, 85/85, 121/121, 8/8, 84/84, 26/26, 33/33 and 59/59.
  The phase's own scripts are `tools/proof/phase5_proof.py` over MCP —
  **88/88** — and `phase5_chrome.py` offscreen — **81/81**, of which
  sections 1–7 (forty-five) are the meter's PICTURE, measured against a
  reference build of the tree one commit before `LevelMeterView.swift`
  existed, section 8 (twenty-three) is its MODEL's reading through the
  harness's third mode, since a meter at rest is all a still frame can hold,
  and section 9 (thirteen) is the EXPORT GAIN over a probe the script
  compiles from `Loudness.swift` alone — the file has no AVFoundation in it,
  so `ExportLoudness.resolve` answers four numbers without a mix, which is
  what lets the −1 dBTP ceiling be swept across two hundred true peaks
  instead of sampled at one.
  **That cross-build comparison is scoped to the TIMELINE BAR**, and
  deliberately: the reference tree ages, so a whole-window comparison would
  fail the first time phase 6 adds an inspector section, with the meter
  untouched and every earlier phase's script expected to re-run unchanged.
  Section 3b stages exactly that (the same reference render against a
  current one whose playhead has moved) and all five of the script's chrome
  mutations were re-measured at the new scoping, so the row costs it
  nothing. The harness's reference build is guarded the same way: one
  GENERAL `-D HARNESS_REFERENCE_BUILD` flag that every future non-render
  mode goes behind, a fallback to the reference commit's own `main.swift`,
  and a scored FAILURE rather than a `sys.exit` when neither builds.

- **Road map 2, phase 6 — Looks: done.** Two schema keys at version 6, TWO
  new ops (`OP_NAMES` 53 → **55**), two new tools (the catalog is **73**),
  and one part of the phase that turned out to be already shipped.
  **`video.blend`** (`core/src/model_props.rs`) is how a layer combines
  with what is already on the canvas — `normal`, `multiply`, `screen`,
  `add`, `overlay`, `darken`, `lighten`, `difference`, the LAST key of
  `VideoProps`. Its **declaration order is a contract**: it is the shader
  discriminant, as `ObscureKind`'s is, `ProjectSnapshot.swift` derives
  `shaderCode` from the case index, and `normal` is 0 with **no `+1`**,
  unlike the filter and obscure discriminants where 0 buys "empty slot".
  There is nothing to reserve — a layer has exactly one mode — and
  reserving it would cost the property that makes the field safe to add to
  a shipped schema: a zeroed uniform block, a recipe from an older core and
  a file with no `blend` key must all render source-over, which is what
  every project drew before the key existed. It belongs to the LAYER and
  not to a source kind, so media, image, still, text and shape all blend
  through one fragment stage — which is what lets the proof use shape cards
  and no media at all.
  **`shape.gradient`** is `null` or `{kind, stops, angle}` — linear or
  radial, 2 to `MAX_GRADIENT_STOPS` = **8** stops, `angle` degrees from the
  RIGHT counter-clockwise (`Shadow.angle`'s convention, the crate's only
  one) — the last key of `ShapeProps`, taking precedence over `fill` while
  it is non-null WITHOUT clearing it, so `{gradient: null}` is an exact
  inverse and the section's Reset brings the colour back. The cap is 8
  where `MAX_FILTERS` and `MAX_OBSCURE` are 4 because those two are SHADER
  SLOTS and this is not a budget at all: `LayerRenderers.renderShape` hands
  the stops to `CGGradient` on the CPU. **The stops are deliberately not
  order-checked** — `CGGradient` needs monotonic locations, but a refusal
  would make dragging one stop past another stop working mid-gesture, so
  the RENDERER sorts, `video.filters` is the precedent, and the proof pins
  that an unsorted list is accepted and draws the sorted ramp so nobody
  "fixes" it into a refusal later. `line` and `arrow` have no area and
  ignore it entirely — stored, range-checked, not drawn, rows disabled —
  which is `shape.radius`'s precedent exactly. Both fields default, so
  version 6 has **no migrate step**, and `format.rs`'s paragraph restates
  the argument in its own words rather than pointing at version 5's: this
  version's loss is quieter still, because a dropped blend removes nothing
  from the picture — the layer is still drawn, just source-over.
  **The renderer is five pipelines from three fragment functions.** Metal
  cannot call one `fragment` from another, so the whole layer stage moved
  into a `static inline layerColorPremultiplied` helper and
  `reelcut_layer_blend_fragment` joined it, reading the destination through
  `float4 dst [[color(0)]]` — programmable blending, no ping-pong target —
  and computing the combination itself; both keep the `kGatherFilters`
  specialization, so four layer states plus the shadow's quad. The refactor
  landed ALONE and phases 1–5 were re-run before a line of blend code
  existed, which is what makes "the plain path did not drift by a bit"
  attributable. `reserved0` became `blendMode`, so the uniform block is
  still 104 floats / 416 bytes and the padding tail is **two**.
  Three things live there, all measured — two traps and one fear the
  mutation run killed. **The two blend pipelines MUST be built with
  fixed-function blending off**, which Metal enforces nowhere and mentions
  never; and **what decides whether the double blend SHOWS is the
  DESTINATION's alpha, not the layer's**. The fragment stage returns the
  finished composite, whose alpha is `as + ab·(1 - as)` — 1 over any opaque
  backdrop, so `oneMinusSourceAlpha` is 0 and an opaque fixture is blind at
  every opacity, half included. The partial-opacity check written for the
  job passed against the broken build; `phase6_proof.py`'s section 6b — a
  translucent DESTINATION, read on the ALPHA channel — is the one that
  fails. **A shadow's mask pass still takes `maskState` and not `state`**,
  because the mask asks about the layer's SHAPE and no blend mode changes
  that — but it is DEFENSIVE rather than load-bearing, and the reason
  everybody gave for it is false: a `multiply` over a destination cleared
  to 0 is NOT 0, since the premultiplied composite's `(1 - ab)·src` term
  reduces the whole formula to `src` at `ab` = 0 for all eight modes, and a
  build passing `state` renders every shadow correctly. Keep the
  separation — it costs nothing and it names what the mask pass means — and
  do not repeat the vanishing shadow. And **this compositor blends in the
  ENCODED sRGB space, deliberately** — nothing uses an `_srgb` format, so
  "multiply of 50 % grey over 50 % grey is 25 %" is a statement about
  encoded values and is false in linear light, where the answer is about
  61/255; a linearise/encode pair would change every blended pixel and make
  the compositor disagree with itself. That sentence is in
  `Compositor.metal`, in the proof's docstring and in spec §7.5. The
  shadow's own DRAW stays fixed-function source-over whatever the mode; the
  REFLECTION inherits the blend.
  **A transition forces `normal`, and the CORE says so** —
  `recipe.rs::layer` emits it for any layer whose `transition` is non-null,
  because the outgoing dissolve's weight correction is the exact algebraic
  inverse of the fixed-function destination factor its partner applies, and
  `add_clip` onto an overlap mints a `cross_dissolve` by default. Do not
  add a second opinion in Swift. The consequence, said out loud because
  from either side it reads as a bug: **the recipe's `blend` is what DRAWS
  and the inspector reads the MODEL's value**, so during an overlap the
  popup says `multiply` while the frame composites `normal`. A **nest clip
  cannot blend at all** (`edit_props.rs`'s `check_blend`, refusing only a
  non-normal MERGED value so `paste_attributes` of an ordinary look still
  works), and `clamp_video` gained an `is_nest` argument to close the
  `set_action_end` back door. A blend on a clip INSIDE a nest is allowed
  and blends against the canvas below the WHOLE nest — an honest limit of
  the same class as a nest's opacity multiplying each inner layer
  separately.
  **The two background ops are `core/src/edit_background.rs`** (508) and
  they are OPS rather than the app-side composite the road map planned,
  because that composite cannot be built (the clipboard payload carries no
  `nests` key) and its repair loses the source WINDOW, so a blurred
  backdrop of a trimmed clip would show different frames from the
  foreground. `add_background` puts a plate — a colour, or a media at FILL
  scale, because a plate that leaves the canvas showing down one side has
  failed at the one thing a background is for — on a NEW back-most track
  for the timeline's length; the default is **white, not black**, since the
  canvas is already black and a black plate is a command that appears to do
  nothing. `add_blurred_background` clones the clip onto a new back-most
  track at `fill_scale` (`edit_clip.rs`'s new sibling of `fit_scale`,
  clamped at the source), centred, uncropped, blended `normal` and blurred
  at 1.0 — and DROPS five things, each a wrong picture or a wrong sound if
  carried: `enabled.audio` (or the mix plays one recording twice, which no
  still frame can see), `audio.duck` (the one field of that group that
  lowers OTHER material, so a copy keeping it would duck the mix including
  the clip it came from), the transition, the actions and the label. It
  refuses a NEST outright, because the flattening drops a nest clip's own
  filters and the copy would come out sharp. Both mint TWO objects and the
  TRACK takes the lower id. Clip ▸ Add Background ▸ Solid Color · Image… is a submenu, not
  a dialog; neither item takes a key equivalent.
  **6d was already shipped** — `set_action_end` has carried
  `video.filters` since M3 and `structural` since phase 3 — so the phase's
  work there was PROOF plus two real defects: an edit to ONE filter inside
  an action re-pinned every other filter's end value (the section built its
  array from the EVALUATED list and `merge` replaces an array whole), and
  `structural` compared a new length against the clip's BASE list while the
  section read the evaluated one, so with two actions on a clip an ordinary
  dial could rewrite the base stack. Both are `InspectorBinding.editedList`
  now: **a write reads the list it is about to REPLACE** — the action's own
  end list, else the base — while every `read:` stays evaluated. Beside
  them, `{"filters": [{"amount": 1}]}` over MCP used to reach the core as a
  BLUR (the decoder fills a missing `kind`) and be reported as success;
  `checkVideoEnums` refuses a partial entry by index now.
  **`gradient` is the first nested object in a patch whose misspelt keys
  are refused BY NAME**, because `shapePatchArg` is hand-built where
  `shadow`, `chroma`, `obscure` and `animation` go through the generic
  decoder that silently replaces. Two size payments came first, both
  before the feature they paid for: `model_props.rs` gave the text
  vocabulary to `core/src/model_text.rs` (252) and is at **600** with phase
  6's additions in it — AT the line, taking nothing further without another
  cut — and `LayerRenderers.swift` gave the text machinery to
  `LayerRenderersText.swift` (577) before the gradient went in, leaving
  467. The two background handlers went into a new
  `AgentServer+Background.swift` (89) rather than into
  `AgentServer+Clips.swift`, which grew to 1183 anyway.
  One thing to know before the next bump: **`{"version": 6}` was the tree's
  "too new, refuse" fixture** in `schema_v3.rs` and `model_tests.rs`, so
  those three tests are at **7** now and each comment says "one past the
  current version" rather than a number.
  Measured: `make test` **436** (368 before — `schema_v6.rs` 17,
  `background.rs` 41 (34 at the landing and 7 more from the review, one per
  behavioural fix), `evaluate_tests.rs` +6 and `schema_v2.rs` +4, which is
  where 6d's tests go because the filter list is version 2's feature),
  `make lint` and `cargo fmt --check` clean, `make typecheck` 0 errors and
  the same 4 AVFoundation warnings, `make app` building, the catalog at
  **73 tools** and the startup parity log EMPTY, and phases 1–5 still
  proving at 66/66, 85/85, 121/121, 8/8, 84/84, 88/88, 26/26, 33/33, 59/59
  and 81/81 — the first group AFTER the fragment stage was refactored, which
  is what says the plain layer path did not drift. The phase's own scripts
  are `tools/proof/phase6_proof.py` over MCP at **167/167** and
  `phase6_chrome.py` offscreen at **70/70**; the split is sharper than any
  previous phase's, because phase 6's two features are PIXELS and the
  offscreen harness can photograph neither — `build.sh` never compiles
  `Compositor.metal` and the preview well is black with no drawable — so
  every blend and gradient claim is the MCP script's and the chrome script
  measures the Blend row, the computed note, the Gradient section and, over
  a probe it compiles because a menu is never drawn into a window, the two
  Clip-menu items and their validator.

- **Road map 2, phase 7 — Output: done.** No project-schema change (version
  6 stands), NO new op (`OP_NAMES` is still 55) and NO new tool (the catalog
  is still **73**) — the first phase whose whole surface is new ARGUMENTS on
  tools that already existed. One new FFI export, three files that paid the
  size rule before a line of feature code, and 170 new checks.
  **The cuts first**: `recipe.rs` 600 → 381 (`recipe_text.rs`, 456, which
  then took the burn-in), `export.rs` 579 → 222 (`export_table.rs`, 509) and
  `ExportSheetController.swift` 1114 → 450 (`ExportSheetOptions.swift`,
  `ExportSheetResolve.swift`, `ExportProgressSheetController.swift`), all
  three PURE MOVES landed and gated alone so anything that moved afterwards
  is attributable. Two more paid it mid-phase: `Exporter.swift` gave up
  `ExporterSettings.swift` before taking its `RecipeOptions` argument, and
  `ExportSheetController.swift` gave up `ExportSheetPresets.swift`.
  **Save Frame** is File ▸ Save Frame… ⌥⌘E, and the shape is the point:
  `FrameWriter.swift` is a value type — a CGImage and a format in, a written
  URL out, no panel and no AppKit view in it — that the panel AND
  `render_frame` both call, which is what makes their PNGs byte-identical by
  construction and is the only way the claim can ever be checked, since a
  save panel cannot be driven over MCP or put up offscreen. PNG keeps a NIL
  properties dictionary; JPEG flattens onto BLACK at 0.9; HEIC is
  `UTType.heic`. `render_frame` gained `path`, `format` and
  `burn_in_timecode`; `replaceableExtensions` gained the five image
  containers, `gif` among them, which fixes a pre-existing `x.gif.png`.
  **`prores_4444`** is a row, and `alpha` in the resolved settings is a
  per-row CAPABILITY — "this encoding carries an alpha channel", true for
  `prores_4444` AND `apng` — never "the canvas is translucent", which would
  report true on an H.264, a GIF and a WAV. `gif` is false although a GIF
  can show a transparent pixel: it has ONE palette index and no partial
  value, where APNG has a real fourth channel. No writer change was needed
  (the codec already mapped, the reader already asked for 32BGRA), and the
  Document tab's alpha control already shipped — what landed there is a
  conditional note. **Two alpha facts were measured, not reasoned**: `apng`
  was written `alpha: false` and is now true, and a ProRes 4444 export at a
  PADDED size wrote INVERTED alpha (the picture at 0, the bars at 255) while
  any same-aspect resize is correct, so `ExportWriter.checkAlphaSurvivesTheSize`
  refuses the aspect change by name. `apng` needs no such guard and must not
  grow one — the ImageIO path FITS instead of padding.
  **The burn-in** is a RECIPE option and never an export override (an
  unknown override key is dropped silently, so the tool would report success
  on an un-burnt file). It travels by `rc_project_frame_recipe_opts`, by
  per-KEY options on `RecipeSource`, AND as a parameter on
  `Exporter.renderFrame` — the third is not redundancy: GIF and APNG never
  reach `ExportWriter`, so the key alone would leave every image-sequence
  export silently un-burnt. The layer is appended LAST, so an un-optioned
  recipe is byte-identical by construction, and `Project::layer` now shares
  its twenty-key skeleton — proved byte-identical against a worktree at
  pre-cut HEAD. Three readings are correct and stated: the placement is a
  FRACTION of canvas height with `valign: middle` (the core stores no
  measured text size), the timecode is NON-DROP, and it shows PROJECT time
  on an in/out export.
  **Presets store CONTROL CHOICES**, not resolved overrides — the road map's
  design could not be built, because the encoding is not an override and a
  resolved map cannot tell "1080p + High" from "Custom + a typed rate". The
  restore ORDER in `loadView` is load-bearing: format before
  `rebuildSizes()`, size after it and by `ExportSize.id` never an index,
  "Custom…" before the loudness field, `resolve()` last.
  **The queue** runs one job at a time from the main thread with a fresh
  `Exporter` each — two concurrent ones DEADLOCK, measured — captures
  `mediaURLs()` at ENQUEUE, and has no AppKit in `ExportQueueController` by
  design, so a probe can drive it where no window can be photographed. It
  gets no MCP mirror: a queue edits no project, and `export` called N times
  already is the capability.
  Measured: `make test` **456** (436 before — `core/tests/recipe.rs` 15,
  `export.rs` 30 → 35), `make lint` and `cargo fmt --check` clean,
  `make typecheck` 0 errors and the same 4 AVFoundation warnings, the
  catalog at 73 and the parity log EMPTY. `tools/proof/phase7_proof.py` is
  **92/92** over MCP and `phase7_chrome.py` **78/78** offscreen, with phases
  1–6 unchanged against the final binary (66, 85, 121, 8, 84, 88, 167 over
  MCP; 26, 33, 59, 81, 70, offscreen). Twenty-four mutants across the two
  scripts; three SURVIVORS were each worth more than a kill — `[:]` for
  `nil` at the PNG add call is a no-op on this OS (byte-identical files, so
  the rule stays as a GUARD and no byte comparison can falsify it;
  `phase7_chrome.py`'s structural read of `destinationProperties != nil` is
  what catches it), the queue's cancel `removeItem` is defence in
  depth because `AVAssetWriter.cancelWriting()` already removes its
  part-file, and the probe's own driving found a latent crash:
  `ExportWriter.cancel` before `reader.startReading()` killed the process,
  which is guarded now.

- **Road map 2, phase 8 — Viewing and finding: done.** No schema change (v6
  stands), NO new op (`OP_NAMES` is still 55) and **NO new tool — the catalog
  is still 73**, which is a decision and not an omission: search, sort and the
  unused filter are view state (`selectedMedia` has never had a mirror
  either), Preview Quality changes nothing an agent can observe, and Reveal in
  Timeline is `set_selection`, which is already a tool. Phases 6 and 7 assert
  `== 73` exactly and still pass.
  Two size tolls were paid FIRST and alone (`d69de99`): `AppDelegate.swift`
  625 → 223 (`AppDelegate+Menus.swift`) and `MediaPane.swift` 822 → 389
  (`MediaRowView.swift`), which cut below the row to take the whole DRAG with
  it, since the pasteboard type, `MediaDropMode`, `MediaDropTarget` and
  `MediaDragSession` exist only to serve it. `MediaPane` then paid a SECOND
  toll mid-phase (`MediaPaneCommands.swift`) — phase 6's warning arriving
  again, that an estimate of what a feature costs here is worth about two
  thirds of the truth.
  **Preview Quality** (View ▸ Preview Quality ▸ Full / Half / Quarter,
  `EditorViewController+PreviewQuality.swift`, key `ReelcutPreviewQuality`)
  scales the PLAYER's render size on a `mutableCopy()` inside `Playback` —
  `ExportWriter.videoComposition`'s shape. `CompositionBuilder.build` is NOT
  touched, and that is the point rather than a convenience: it is the app's
  ONE constructor of `AVMutableVideoComposition`, shared by the preview, both
  export passes and the offline frame, so an argument there would leave the
  export one wrong parameter away from the preview's setting. With the copy,
  the export and `render_frame` paths are UNREACHABLE from the setting rather
  than merely unchanged by it, and `phase8_proof.py`'s byte comparisons are
  true by construction. The size always carries the canvas's EXACT aspect
  (`m · (w/g, h/g)`, `g = gcd(w,h)`, `m = ceil(g/divisor)`), falling back to
  the next COARSER exact size and finally to Full for a coprime canvas like
  1001×667, because `PreviewCanvasView` maps every drag handle through
  `AVPlayerLayer.videoRect`. Odd render dimensions were measured LEGAL, so the
  rule is about aspect, not legality. **Do not put a preview-shaped argument
  on the shared builder.**
  **The preview window** (⇧⌘P, `PreviewWindowController.swift`) is a second
  `AVPlayerLayer` on the SAME player. Apple's ARCHIVED AVFoundation guide says
  only the most recently created layer displays; that was SPIKED before a line
  was written and is stale on macOS 26.5.1 — two layers, both creation orders,
  byte-identical `displayedPixelBuffer`s over eighteen probes, and releasing
  the second leaves the first displaying. **Carry the spike's other finding
  forward: `isReadyForDisplay` and `videoRect` are useless as instruments** —
  a layer with no superlayer and a layer in a never-shown window both report
  `true` with a plausible rect, and `displayedPixelBuffer` is the only
  property that discriminates. It is an **`NSPanel`**, measured: a titled
  `NSWindow` becomes key AND main and every editor selector then resolves to
  NONE, so ⌘E / ⌘T / ⌘0 go dead while the preview is focused. Retention is one
  stored property on the frozen `EditorViewController`, NOT
  `document.addWindowController(_:)` — also measured: AppKit asks a document
  about saving only when the controller closing is the LAST one, so with two
  controllers a dirty document's close put up no sheet, destroyed the editor
  window and left the document open behind a panel with nothing to edit in.
  The controller is also the panel's DELEGATE, for `windowWillReturnUndoManager`
  alone: `undo:` is not an editor selector but one `NSWindow` implements
  itself, so without it the search stops at the panel's own empty manager and
  ⌘Z is dead in the one window a person can edit from.
  **The Media tab** gained a 60 pt find band — search, a sort popup and an
  "Unused only" switch — plus Reveal in Timeline
  (`MediaListFilter.swift`, `MediaPaneCommands.swift`, `MediaUsage.swift`,
  `MediaReveal.swift`). The band **never rebuilds the pane**: rows that already
  exist are hidden and re-ordered in place, because `InspectorPaneView.rebuild()`
  removes every arranged subview and the inspector preserves no first
  responder, so a field built inside `makeSections()` loses its caret on the
  first keystroke. The sort row is **"Import Order"** and not the road map's
  "Added", because nothing records when a file arrived and a timestamp would be
  a version-7 bump. Fixed on the way through, and not strictly the phase's:
  **"is this media used" was written out twice in Swift and both spellings
  missed nests**, so removing a file used only inside a nest gave a bare beep
  with no reason in it; and the Media tab's Relink… was the only one of three
  relink paths that never regenerated caches.
  **8d is the review's blocker, and it is the one to remember.**
  `[[position]].xy` arrives in DESTINATION pixels and three shader tests took
  it to BE canvas pixels — a nest's `clip_rect`, the drop shadow's mask
  sample, and the outgoing dissolve's partner box. For the app's whole history
  the two were equal, so the assumption was true, was written into three
  comments AND into `core/src/nest.rs` and spec §7.3, and was invisible.
  Preview Quality made the destination smaller and it became a wrong PICTURE:
  three quarters of a nest erased at Half and all of it at Quarter, a shadow
  displaced to the corner or gone, a dissolve losing its weight correction.
  `LayerUniforms`' last two padding floats are `canvasPerDestX/Y` now (the
  block is still 416 bytes and **the tail is EMPTY** — the next field needs
  three companions), `ShadowUniforms` went 8 floats to 12, and a non-positive
  ratio reads as 1 so a zeroed block renders what it always did. **An
  invariant that holds because two numbers have always been equal is not an
  invariant.**
  Measured: `make test` 456 unchanged, `make lint` and `cargo fmt --check`
  clean, `make typecheck` 0 errors and the same 4 AVFoundation warnings,
  `make app` building, the catalog at 73 and the parity log EMPTY.
  `tools/proof/phase8_proof.py` **79/79** over MCP — its headline is two
  INSTANCES of one binary, one launched `-ReelcutPreviewQuality 2`, whose
  `render_frame` PNGs and `apng`/`gif` exports are byte-identical — and
  `phase8_chrome.py` **144/150** offscreen, the six being section 4's dispatch
  checks, which fail on their own PRECONDITION because this machine's console
  was LOCKED and no process can activate. Phases 1–7 re-run unchanged (66, 85,
  121, 8, 84, 88, 167, 92 over MCP; 26, 33, 59, 81, 70, 78 offscreen), the
  last group AFTER the shader change. Ten mutants, two survivors, both
  reported. **The most valuable result was a kill that did not happen:
  `phase8_proof.py` as first written scored a clean 65/65 against a build with
  Preview Quality deleted outright** — section 5, a probe reading the render
  size off a real `AVPlayerItem`, is what closes it, and both numbers are in
  its docstring. Nineteen of 33 review findings survived their sceptics.
  Two limits recorded rather than fixed here: `selectedMedia` can point at a
  row the filter has hidden, and `ProjectDocument.generateCaches`'s "a cache
  already on disk is not rebuilt" was FALSE — measured, it re-decoded — a
  wrong comment and wasted work, not a wrong picture. The second was fixed
  after the road map closed, by making the sentence true (the completion
  marker, in "After road map 2" below).

- **Road map 2, phase 9 — Inside the nest: done.** The largest item, and the
  one the spec designed and left (§4.4). No schema change (v6 stands), NO new
  op (`OP_NAMES` is still 55), ONE new tool (`set_scope`; the catalog is
  **74**) and ONE new FFI export. **Road map 2 is now complete.**
  Every op's clip argument used to resolve through `Project::clip`, which
  searches the top level only. The answer was NOT to teach 55 ops about nests
  but to give the op a **scope**: `scope?: u32` is an envelope key on
  `rc_project_apply`, and with one the core builds a VIEW project from the
  named nest, applies the op to it UNCHANGED, and merges back
  (`core/src/scope.rs`). **`Project::clip` still means exactly what it always
  did** — in the view, the nest's clips ARE the top level.
  **The envelope could not simply gain a key.** `Op` is internally tagged with
  `deny_unknown_fields`, so a top-level `scope` is an unknown field for all 55
  variants (measured against the shipped build first), and `#[serde(flatten)]`
  is not the way round it — serde does not support the two together. `parse`
  was already a two-pass parse holding the envelope as a `Value` to read
  `"op"`; it takes `scope` out in that same pass and answers an `Envelope`.
  **THE VIEW'S SHAPE, and the part that is counter-intuitive**: canvas SIZE =
  the nest's frozen size, the rest of the canvas = the parent's;
  `tracks`/`clips` = the nest's; `media` = the parent's; `markers` = none;
  `next_id` = the parent's; and `nests` = the parent's **with the scoped nest's
  own tracks and clips EMPTIED — kept, not removed.** Leaving the row whole
  doubles every id in `validate`'s one uniqueness sweep; taking it out dangles
  every OTHER nest's reference to it, which is exactly the nest-inside-a-nest
  case the phase exists for. That second half was found by a FAILING TEST and
  by no reader.
  **THE ERR ARM IS WIDER THAN ANY UNSCOPED OP'S.** `check_caps` sums the
  timeline's clips with every nest's and `check_nesting` starts every walk at
  level 1, so neither can be seen from inside a view; both are checked once, on
  the MERGED parent. **An op can be perfectly valid inside the nest and the
  scoped apply still return `Err`** — do not assume a valid scoped edit landed.
  **Seven ops refuse a scope** by name — the three marker ops, `set_canvas`,
  and the three media ops — and `refused_inside` is an EXHAUSTIVE 55-arm match,
  so a later phase's op will not compile until it is classified.
  **`rc_project_scoped`** (`ffi.rs`, beside `rc_project_clone`, NOT in
  `ffi_query.rs` whose doc says a query never allocates a handle) is the READ
  half: the app plays, plans, renders and snapshots what is inside. It CALLS
  `scoped_view` rather than building a second view — a read view differing from
  the edit view would make the timeline show one project while the edits landed
  in another.
  **The app** holds a `nestPath` — a stack of (nest, clip) steps and NOT a bare
  nest id, because a nest can be shown by TWO clips at two different starts — a
  STORED memoised scoped handle (`ReelProject` memoises per handle; ~78 read
  sites would otherwise re-decode), and one accessor `editedProject`, with
  `project` still meaning the PARENT for save, export and consolidate.
  `clampViewState` clears a dead scope FIRST and then the selection, and that
  order is load-bearing. ⌘↓ / ⌘↑ and a double-click enter and leave (a nest
  clip loses rename-by-double-click); a breadcrumb sits in the ruler's corner.
  **The rule the review carved out, and the one to remember: a nest-local
  number spent as project time.** Three survivors were that shape — Save Frame
  rendered the DOCUMENT at a nest-local playhead, an in/out range set inside a
  nest was exported as project time, and `add_marker` over MCP placed at a
  nest-local tick while the UI had already refused exactly that. So: **a
  producer reads the container it writes into** (the captions group was the
  same defect in four more files), and **a range belongs to the container it
  was set in and never leaves it** — refused rather than mapped, because a nest
  clip is TRIMMED and a mapped range can name content that was never on screen.
  Two more with teeth: a REVERT left `nestPath` and the memo pointing at a
  discarded document, after which EVERY edit was refused with `no nest with
  id N`; and the breadcrumb was invisible whenever the timeline was scrolled,
  because the header column sat ABOVE the floating ruler — **wrong for eight
  phases at the top level too**, and invisible to every proof script, since
  every harness render is at scroll 0.
  Measured: `make test` **494**, `make lint` and `cargo fmt --check` clean,
  `make typecheck` 0 errors and the same 4 AVFoundation warnings, `make app`
  building, the catalog at 74 and the parity log EMPTY (the check has FOUR
  parts now — the fourth asserts every op tool declares `scope`, and is the
  only mechanism that would catch the 56th op added without one).
  `tools/proof/phase9_proof.py` **184/184** over MCP at the landing — its spine
  is the oracle, "apply inside with `scope`, then `unnest`" equals "`unnest`,
  then apply at top level" over fourteen ops, ids aside, with every row ALSO
  asserted to differ from the untouched round trip — and `phase9_probe.py`
  **48/48** over a probe compiled from the whole of `app/Sources`. Phases 1–8
  re-run unchanged: 66, 85, 121, 8, 84, 88, 167, 92, 79 over MCP and 26, 33,
  59, 81, 70, 78, 150 offscreen. The phase shipped two review-wave fixes with
  only UNTRACKED instruments behind them, and the debt was paid after the road
  map closed: `phase9_proof.py` is **214/214** since its section 9 (the
  inherited-scope marker refusals and the landing a result reports; two
  mutants, 209/214 each), and **`phase9_chrome.py` — 62/62 — photographs the
  ruler corner SCROLLED** through a probe compiled from `app/Sources`, which is
  the only way the z-order defect above can be seen (three mutants: 52, 57, 55
  of 62). **Twenty-four mutants, two survivors, both reported.** The core's
  survivor was EQUIVALENT there and the MCP script KILLED it, because
  `get_project` inside a scope reports the view — a view somebody can look at
  is a contract. And the mutant giving the view the PARENT's canvas would have
  SURVIVED the frame-region comparison alone, since inner and outer then have
  the same size and the comparison degenerates into a whole-frame identity.

- **After road map 2 — the remainder: done.** `designs/reelcut-remaining.md`
  §1 and §2 are closed and carry the record; §3–§5 are what is still open.
  Four items, no schema change, no new op, no new tool (the catalog is still
  **74**), one size toll paid alone first (`3e5b598`).
  **§1a** — the 28 marker-scope checks phase 9's fix wave measured with an
  untracked script are `phase9_proof.py`'s section 9 (30 with a tightened
  check and two the fold added; **214/214**; the two mutants — the refusal
  made a no-op, the landing echoed unconditionally — score 209/214 each,
  five named failures apiece). The doc said 29; the 29th was `def check`.
  **§1b** — **`phase9_chrome.py`, 62/62**, route 1 over a probe: six scenes
  of a bare `TimelineView` over an honestly scrollable ten-track fixture (the
  untracked six-track one had OVER-SCROLLED through `NSClipView.scroll(to:)`
  — its content was shorter than the pane, and a tracked script should not
  claim a state the app cannot reach), the corner byte-compared as a decoded
  crop, and the gesture half read as the `Equatable` `TimelineHit`. Its gate
  is a MUTANT on a copy of `app/Sources` because no git commit has the old
  z-order WITH a breadcrumb: init order swapped 52/62, `endRename`'s restore
  deleted 57/62 (a fifth scene ends a rename, which the untracked probe never
  did), the double-click guard flipped 55/62.
  **§2a — the cache completion marker.** The decision the doc asked for: not
  a doc-only fix (every open of a saved project would keep re-decoding every
  filmstrip and re-reading every audio track) and not a plain existence
  check (`relink_media` keeps the media id, so `thumbs/<id>/` already exists
  with the OLD film's frames and a relinked media would never get new ones —
  a wrong picture, and Remove Silences and Normalize would measure the old
  file). `CacheStamp` (`MediaCacheFiles.swift`, spec §5.6) is the source's
  size and modification second plus the record fields and constants that
  size a cache, written LAST as `thumbs/<id>/complete.json` and
  `peaks/<id>.complete.json`, and it carries NO path — unlike the reversed
  cache's digest, which names a file in a shared directory — so a moved
  package, a consolidated copy and a copy on another disk keep every
  filmstrip. `generateCaches`'s task stats the file ONCE and hands the stamp
  to both halves; `thumbnails` and `peaks` compare it with their marker at
  the head and return without decoding when it matches; a relinked,
  changed, partial or unmarked cache is deleted — the old frames, or the old
  `.bin`, whose withdrawal is POSTED at once so nothing measures the
  previous file's sound meanwhile — and rebuilt, and the marker is written
  LAST and only for a strip the pass can vouch for (at least one frame
  landed and every frame it wrote is still there: a save of a titled
  document mid-pass swaps the package under it and loses the frames written
  between the listing and the swap, and a reader that fails on every frame
  would otherwise certify an empty strip — both leave no marker and the next
  open rebuilds, as before). The FIRST post of a replacing pass says
  `replaced`, and `TimelineView.swift` took five wiring lines so the
  timeline drops that media's decoded tiles only then (`TimelineCaches`
  kept hits on purpose, for the fill-in case, and a relink used to leave the
  old film on screen until the 800-entry drop — pre-existing). Passes for one
  media run one at a time IN CALL ORDER through `CacheLedger`, an `NSLock`
  rather than an actor, because a pass carries the URL the media resolved to
  when asked and two `Task` hops from one thread are not ordered; its price,
  recorded, is that a pass stuck inside one AVFoundation call holds a relink
  away from the stalled file. Seven comments that stated the false sentence
  now state the true one, and `MediaImporter.generateCaches`'s "a cancelled
  import (the document closing)" — a case that does not exist; nothing
  cancels the task — names the real partial cases. The size toll came due a
  second time mid-fix (644 against the cap), paid by moving the peak-bucket
  arithmetic next door as `PeakBuckets`, byte-identical output against the
  pre-move binary; 586 and 490 after.
  Measured: `remaining_proof.py` **79/79** over MCP (inodes and nanosecond
  mtimes across a 3 s window, bounded by a positive control whose measured
  rebuild latency — 0.06 s here — is asserted inside that window;
  `copyItem` preserves `st_mtime_ns`, so Consolidate rebuilds nothing; a
  relink to a file with no audio track withdraws the `.bin` and
  `detect_silence` reports the media pending instead of answering from the
  old file) and `remaining_probe.py` sections 2–5 (the stamp as pure calls,
  the ledger as a post count, the stale tile as pixels, and the pass's own
  rules — a frame deleted mid-pass, an unreadable file, a failed image
  decode, one `replaced` post, the withdrawal). Twelve mutants across the
  two, no survivor: the thumbs head check deleted 65/69, `modified` forced
  to 0 59/69, a 4 s sleep after the head check 67/69 (only the latency
  bounds), the peaks head check deleted 75/79, `clearPeaks` back to
  marker-only 76/79; the ledger removed 107/108, the hit-clearing removed
  105/108, the presence check removed 138/141, its empty-set guard removed
  139/141, the withdrawal's probe half 139/141, the image post moved back
  140/141, `replaced` on every post 140/141. The review of the first landing
  is what forced the vouching rule and the withdrawal — a lane that had
  passed its own gate still had two defects a reader with a different
  question found. Recorded, not fixed: `relink_media` never re-probes, so a
  relink to a file of another length sizes the new strip from the old
  `duration`; and an open Remove Silences sheet re-reads on a peaks post only
  while something is pending, so spans it measured from a file an MCP relink
  then swapped away (the sheet is modal, so nothing else can) stay until it
  is reopened.
  **§2b** — the item's premise was half wrong. `CaptionExporter`'s format
  popup wanted a `{srt, vtt}` set (`CaptionExporter.renamed`,
  `FrameWriter.renamed`'s six lines), but its other site strips the
  DOCUMENT's extension off a title-bar name, and so did two siblings the
  scout found (Save Frame's stem, the export sheet's `suggestedName`): all
  three now read `ProjectDocument.displayStem`
  (`ProjectDocument+DisplayStem.swift`, set `{reelcut}`, an extension because
  the base file is over the cap). Both sites are PANEL-only and the MCP path
  was right all along, so an MCP check passes against the unfixed build; the
  proof is `remaining_probe.py`'s section 1 over tables — which is also the
  first instrument to call `FrameWriter.renamed`, whatever its docstring
  claimed since phase 7 — plus a structural read that the four sites CALL
  their helpers (an unwired site scored 60/60 on the behavioural rows; three
  mutants 59, 60, 60 of 63). Recorded limit: `chart.png` under SubRip is
  `chart.png.srt` in the panel and `chart.srt` over MCP.
  Measured for the lot: `make test` 494, `make lint` and `cargo fmt --check`
  clean, `make typecheck` 0 errors and the same 4 warnings, the parity log
  EMPTY, every phase proof unchanged against the final binary, and the
  offscreen list is now 26, 33, 59, 81, 70, 78, 150, 48, 62, 170 (the last
  was 101 when this paragraph was written and 141 by the time it was read;
  road map 3's held tail took it to 170).

- **Road map 3, phase R1 — screen recording: done** (2026-09-11). The
  feature spec §1 named a non-goal on day one, reversed by a recorded
  decision (§11): the app records a display or a window through
  ScreenCaptureKit into `~/Movies/Reelcut Recordings/` and imports the file
  exactly as File ▸ Open would. No schema change (v6 stands), NO new op
  (`OP_NAMES` is still 55), ONE new tool (`record_screen`; the catalog is
  **75**), no FFI change, three size tolls (`AgentCatalog+Files.swift` first
  and alone; `MediaImporter+Probe.swift` and `AgentServer+RecordingArguments/Result.swift`
  mid-wave) and nineteen new Swift files under a 400-line cap each.
  **The spike ran before the code and overturned the plan twice** (R0, in
  `designs/reelcut-roadmap-3.md`, dated): `SCRecordingOutput` folds a
  microphone INTO the system-audio track — one stereo track, inseparable,
  clipping when both are loud — so the microphone is a SECOND FILE through
  an `AVCaptureSession` + `AVCaptureAudioFileOutput`, landing as its own
  clip on a "Microphone" track at the offset the two did-start callbacks
  measure; and `captureResolution .best` scales nothing, so pixels are asked
  for by hand. It also found what nobody asked: **a recording's VIDEO track
  ends at the last screen change**, and AVFoundation inserts the uncovered
  range without clamping and renders it BLACK — `CompositionBuilder.fill`
  now holds a video track's last frame over any part of a segment's source
  range the track does not cover (spec §7.2), and `MediaImporter.thumbnails`
  holds it in the strip from the track's last sample's own time. A shell-
  launched instance is attributed by TCC to its TERMINAL (R0 q1), which is
  why every proof's instance runs under ghostty's grants and the refusal
  sentences name the launching process's pid. **The recorder never prompts
  and the panel asks for both grants on a press** (decision 4); the canvas
  of a new project takes the panel's 30 or 60 while the media keeps the
  file's honest variable rate (24981/1000, 42381/1000, 21410/1000 measured);
  undo of Add Recording leaves the file. `ScreenRecorder` is a machine
  `idle → arming → recording → finishing → idle` whose every framework
  callback is stamped where it lands and hopped to main; its `onFinish` is
  the one hook, on the session, called exactly once; a `stop()` past idle
  JOINS the finishing under way; a microphone problem is `micProblem` on a
  `.success` and never the recording's failure; the capture session is
  prepared during the countdown (a smoke run had lost the first 421 ms of
  voice). **Reviewed by nine readers, 68 findings; eleven confirmed by every
  refuter, two refuted, fifty-five never judged (the usage limit killed the
  refuters) and triaged by hand; a two-stage fix wave closed them by root
  file with a mutant each** — road map 3's record lists them.
  Measured: `make test` 494, `make lint` and `cargo fmt --check` clean,
  `make typecheck` 0 errors and the same 4 AVFoundation warnings (now at
  `CompositionBuilder.swift` :368/:401/:446 and `Exporter.swift` :595 — the
  file reads `minFrameDuration` and `nominalFrameRate` by KEY, because the
  baseline counts a deprecation diagnostic per USE SITE), `make app`
  building with the audio-input entitlement in the signed binary, the parity
  log EMPTY, and every earlier proof unchanged against the final binary: 66,
  85, 121, 8, 84, 88, 167, 92, 79, 214, 79 over MCP and 26, 33, 59, 81, 70,
  78, 150, 48, 62, 170 offscreen. The phase's own: `recording_spike.py` (six
  answers), **`recording_proof.py` 152/152** on this host with the two tone
  rows skipped BY NAME — a Bluetooth or muted output hands the system-audio
  tap nothing, and a locked console shares no display; **host state is a
  proof input, read and named, never assumed** — and **`recording_probe.py`
  662/662** over a probe compiled from the whole of `app/Sources`, whose
  section 3 drives a FAKED session (an `SCContentFilter()`, an `SCStream`
  and an `SCRecordingOutput` all construct without a grant) and whose
  twenty-odd named mutants score 613–661 of 662. Two things the phase found
  in older ground: the harness pinned keys by SYMBOL and `phase5_chrome.py`
  had been comparing two builds of its instrument since phase 8 without
  saying so (`MediaSearchField` outside the `HARNESS_REFERENCE_BUILD`
  guard) — both literalised or guarded, and phase 5 compares one program
  again; and `AVAssetImageGenerator` fails INSIDE a non-sync frame's range
  on an ffmpeg-made sparse file (−11821) while a real recording lands every
  second, which `remaining_probe.py` 5f pins. What only a person can check
  is in `reelcut-remaining.md` §4: the picker from a non-activating panel,
  whether a picked recording contains the panel (moot since R2 — it orders
  out for every source), the countdown's look, the menu bar's own
  indicator, and the microphone prompt from the signed bundle.

- **Road map 3, phase R2 — pause and resume, and the panel that goes away:
  done** (2026-09-12). Two decisions recorded before the code (spec §11):
  **a paused recording is a SEQUENCE of files over ONE stream**, because
  ScreenCaptureKit has no pause and the only lever is removing the
  recording output (its file closes) and adding a fresh one while the
  stream keeps capturing — spiked as R0's seventh question before the
  plan leaned on it (remove → did-finish 5–25 ms, add → did-start 8–10 ms,
  57 fps through the pause; a Bluetooth headset's first use poisoning the
  microphone writer was the one host fact) — and **the panel orders out at
  the start of EVERY recording and comes back only with something to
  say**; the menu bar's status item is the recording's whole chrome, Pause
  Recording · Stop Recording, then Resume Recording · Stop Recording while
  paused, the coral dot swapped for a pause glyph with the time FROZEN. No
  schema change (v6 stands), NO new op (`OP_NAMES` is 55), NO new tool
  (the catalog is still **75**; `record_screen`'s result grows `pauses`
  and `segments`, `duration` becoming the total), no FFI change. Two pure
  moves paid the toll first and alone (`91fb287`: `RecordingResult.swift`,
  `RecordingLanding+Microphone.swift`); three more files are new
  (`ScreenRecorder+Pause.swift`, `RecorderPanelController+Pause.swift`,
  `RecordingLanding+Placing.swift`) and one is a mid-phase pure move
  (`ScreenRecorder+Delegates.swift`); `ScreenRecorder.swift` (399) and
  `AgentServer+Recording.swift` (400) are AT the 400-line cap.
  **The machine** (`ScreenRecorder+Pause.swift`): `idle → arming →
  recording ⇄ paused → finishing → idle`; a `Session` holds `segments`,
  never empty, and every framework callback finds ITS segment by the
  output's identity or the microphone file's URL, because a closed
  segment's did-finish can land after the resume and a resume never waits
  for it; `elapsed` is the segments' spans summed, frozen while paused;
  each segment carries its OWN measured microphone offset (q7: −22 to
  +33 ms across resumes); a stream that stops while PAUSED lands what was
  recorded rather than failing it, since every file is closed; `pauses`
  is a stored count of Pause presses. **The landing** places the pictures
  back to back on ONE track, every `add_clip` READ BACK — at an inexact
  canvas rate (decision 3's 24981/1000) the previous end is not a grid
  point and a raw add snaps DOWN into a one-tick overlap the core dresses
  as a cross dissolve, so the rule is touching or a sub-frame gap, never
  an overlap; each voice on one Microphone track at its picture's start
  minus its offset, floored at the previous voice's end with the head
  snapped BEFORE the floor test; a voice shorter than its head (the
  `trim_start` clamp would leave a one-frame sliver and a REFUSED
  `move_clip` riding the committed list) and any file under a frame (R0
  measured a real 2 ms microphone file) land as media with a note naming
  the file, and `Placement`'s four id lists have one entry per segment,
  nil where nothing was minted. A new project's remainder is one undo
  step, "Add Microphone" for one segment with a voice, else "Add Recording
  Segments". **The chrome**: a refused resume's sentence is STATE
  (`resumeProblem`) so the panel can come back and say it; the welcome
  button has its own selector (it used to STOP a running recording through
  `newRecording`'s first arm — inherited from R1 and invisible until the
  panel hid); ⌘Q while paused opens the item's menu; the item freezes at
  Stop. **Reviewed by four readers, twenty-nine findings, fixed by root
  file with a mutant each** — road map 3's R2 record lists them.
  Measured: `make test` 494 and `make lint` clean stand (no Rust change),
  `make typecheck` 0 errors and the same 4 AVFoundation warnings,
  `make app` building, the parity log EMPTY; `recording_proof.py`
  **187/187** with the two tone rows skipped by name; `recording_probe.py`
  **876/876** over a probe from the whole of `app/Sources` (662 before the
  phase; twenty-nine mutants, every one killed, the R2 nine at 811–875),
  its section 9 a real two-segment recording under the terminal's grant —
  skipped by name, 41 rows counted, on the locked console it landed on,
  and measured ONCE when the display woke mid-sweep: the panel hidden at
  the start and still hidden after a clean landing, two segments, the
  did-finish 0 ms after the remove and the did-start 23 ms after the add;
  every earlier proof unchanged against the final binary — 66, 85, 121,
  8, 84, 88, 167, 92, 79, 214, 79 over MCP and 26, 33, 59, 81, 70, 78, 150
  (144 on this locked console — section 4's six dispatch checks fail on
  their own precondition, the known state), 48, 62, 170 offscreen.
  What only a person can check is in `reelcut-remaining.md` §4: the
  item's two menus and the glyph, the system indicator through a pause,
  the panel gone for a display source and back only with a note, ⌘Q while
  paused, and a paused recording played across its segment boundary.

Keep this file current as code lands.
