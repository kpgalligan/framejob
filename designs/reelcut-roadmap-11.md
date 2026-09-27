# Road map 11 — Seeing the screens

Two needs, one instrument. **An agent should be able to look at the running app's chrome** —
to debug a layout without a person describing it — and **a person should be able to export
named screens with a description of each**, to draft design requests to Claude Design.
Agreed with the user 2026-09-26; the decisions it rests on are spec §11 V-1..V-3
(`designs/spec/11-decisions/dev-tools.md`).

What exists: the offscreen harness (`tools/proof/harness/`, CLAUDE.md "Seeing the chrome")
already `cacheDisplay`s an `EditorViewController` into a PNG with no TCC grant. It is kept, and
stays the instrument for byte-identical proofs. What it cannot do is why this road map exists:
it renders only what a package on disk plus a dozen positional arguments can describe — never a
sheet, a panel, a state reached by editing — its preview well is black, and its argument list
was built for proof scripts rather than for looking.

The shape: **dev-only MCP tools in the running app** (V-1), capturing through the same
`cacheDisplay` path (V-3), plus a **screen catalog** in `tools/proof/` that drives the app into
named states and writes each screen with its description.

## Phases

Each phase is one litecode pipeline, in order; each is provable alone.

### V0 — the build flag and `make dist`

- `REELCUT_DEV_TOOLS`, a Swift compilation condition. `project.yml` declares three
  configurations — Debug, Release, **Distribution** (a copy of Release) — and sets the flag in
  `SWIFT_ACTIVE_COMPILATION_CONDITIONS` for Debug and Release only. `make app` is unchanged: it
  builds Release, so every proof and every agent session has the dev tools.
- `make dist` builds Distribution into its own products folder, then **checks the binary**: the
  dev tools' names are absent from the Distribution binary AND present in the Release one (the
  positive control — without it an absence check passes against a build that never had them).
  The check is a script under `tools/proof/`, called by the Makefile, and a failure fails `make`.
- `make typecheck` and `tools/proof/harness/build.sh` pass `-D REELCUT_DEV_TOOLS`, so the
  flagged code is typechecked and the harness links what the app links. The flag-OFF path is
  compiled by `make dist` alone; say so in the Makefile comment.
- The seam, written first: `AgentServer+DevTools.swift` holds `#if REELCUT_DEV_TOOLS` a handler
  table and catalog rows, `#else` two empty ones. Swift takes no `#if` inside a dictionary
  literal, so `AgentServer.swift` (frozen) takes one line of wiring — `handlers` merges the dev
  table — and `catalogJSON()` appends the dev rows. The parity check, the gate and the schema
  checks then cover dev tools with no change, in both builds. V0 lands with the tables EMPTY
  and proves `make dist`'s check against a placeholder name.
- Proof: `make dist` passes; with the flag forced on in Distribution it FAILS (the mutant);
  both builds start their agent server with `grep "Reelcut: "` printing nothing.

### V1 — spike: the preview well and the sheets

Two questions a plan cannot answer from the SDK docs, run before V2 is designed:

1. `cacheDisplay` in the live app draws the preview's `AVPlayerLayer` (and any Metal content) as
   black. Can `render_frame`'s picture for the playhead be put UNDER the canvas overlay for the
   capture — a temporary layer or view beneath the overlay, removed after — so handles and
   guides land on top as on screen? Or must it be composited after, painting over them?
2. A sheet is a window of its own in the live app. Does `cacheDisplay` of
   `window.attachedSheet`'s content view give the sheet, and can a sheet be put up
   programmatically (a menu item's action) without a modal run loop blocking the main thread
   that every MCP call hops to? Which of the app's 34 sheet sites use `runModal`, and so must
   never be triggered by a tool?

The answers go in this road map's V1 record and bind V2's design.

### V2 — `snapshot_ui` and `perform_menu_item`

- **`snapshot_ui`** (main thread; not in `offMainTools`). Arguments: `window` — `editor` (the
  key document's), `sheet` (its attached sheet), `settings`, `welcome`, or omitted to LIST the
  open windows with their titles and sizes; `view` — a named region (`toolbar`, `preview`,
  `inspector`, `timeline`) or the whole window; `appearance` — `light`, `dark`, or the
  window's own, set on the live window for the capture and restored after (V1's A3–A6: the
  switch and the restore are byte-identical to a fresh window and to the capture before);
  `path`; `fill_preview` (default true): `render_frame`'s picture put UNDER the canvas overlay
  for the capture and removed after, so handles and guides land on top as on screen (V1's
  W4a–c; W6 is what leaving it in costs). A `sheet` that is a file panel (`NSOpenPanel`, an
  `NSRemoteView` drawn out of process) captures as one colour (V1's S2c); the tool says so
  rather than returning it. Returns the PNG as an MCP image block AND a path, the way
  `render_frame` does, so an agent sees it and a script can diff it.
- **Neither tool may depend on the app being active or its window visible.** An agent drives
  the app while the person works in other apps, so the editor is usually behind their windows:
  V1's placed probe read occluded, and did not activate, in two runs with a person's windows
  over it, and scored every row in the next two. `snapshot_ui` captures with `cacheDisplay`,
  which the offscreen harness already shows needs no window on screen. `perform_menu_item`
  must deliver to the named document window's own responder chain rather than through a
  nil-targeted `performActionForItem`, which reaches `EditorViewController` only while the app
  is active and that window key (V1's S0 checked both before S1 ran). V1 did not score a
  capture or a delivery with the probe inactive and occluded; V2's design owes those two rows
  before it leans on this bullet.
- **The layout dump comes with it** (`layout`, default true): a JSON file beside the PNG — per
  view its class, accessibility identifier, frame in window points, hidden, and the text of a
  label or button — and a `problems` list the tool computes: views with
  `hasAmbiguousLayout` (AppKit's private `_NS…` subviews listed apart, not as problems: V1's
  L3 found three inside the Text sub-tab's text view in the one editor state it measured), views extending past
  their superview's bounds, and text fields whose intrinsic width exceeds their frame
  (truncation — the shape of #70). For layout debugging the numbers are the answer; the
  picture is the check.
- **`perform_menu_item`**: a menu path (`["File", "Export…"]`) run with
  `performActionForItem`, answered only after the run loop settles. It is what puts a sheet,
  the Settings window or a panel up for `snapshot_ui`: in V1's S1 rows Export…, Remove Track
  and Add Media… each had its sheet attached when the call returned (295–761 ms), with no modal
  window and the main queue not run inside the call. It refuses a disabled item, and it
  refuses by name every item whose selector V1's inventory
  (`tools/proof/capture_spike/inventory.json`) reads `modal` — Tools ▸ Allow Agent Connections —
  or `framework` — the sixteen AppKit-owned items, among them Quit, Open…, Save, Save As…,
  Revert to Saved, Close and Help, which the spike read and did not run.
- Both live in `AgentServer+DevTools.swift` and a capture file of their own
  (`UISnapshot.swift`, under the flag), each under the 400-line cap.
- Proof (`tools/proof/v2_snapshot.py`): two snapshots of one state are byte-identical; a
  `set_selection` changes pixels only inside the inspector's and timeline's rects; a sheet
  opened by `perform_menu_item` (an app sheet, such as Export…'s) is captured and closed; the
  layout dump's problem list names a deliberately ambiguous constraint (the mutant) and is
  empty without it; the preview well shows the picture when `fill_preview` is on and the
  canvas background when off.

### V3 — the screen catalog

- `designs/screens/`: one Markdown file per screen — a front block naming the screen, the MCP
  steps that reach it (open this fixture, select that clip, open this sheet), the windows and
  regions to capture, and the prose: what the screen is for, what the person there is trying
  to do, what the parts are. Prose lives in the repo so it is changed with the screens.
- `tools/proof/screens.py` (over `mcp.py`, dependency-free): launches its own instance, builds
  the fixture projects it needs from the proof media, walks every screen file, captures light
  and dark, and writes `tools/proof/work/screens/<date>/` — the PNGs and one `screens.md`
  pairing each image with its description, ready to attach to a design request. A screen whose
  steps fail is a scored failure in the output, never a silent gap.
- First catalog, about a dozen: welcome; the empty editor; an editor with video, text and a
  graphic; the Clip inspector's tabs; the Document inspector; Settings; the Export, Speed,
  Remove Silences and Generate Captions sheets; the recorder panel.
- Proof: the run is complete, and a screen file with a broken step is reported as failed.

### Closing

Spec §7.9 (the dev tools, and that they are absent from Distribution), §7.4's file map,
`app/CLAUDE.md`'s map entries, root `CLAUDE.md`'s "Seeing the chrome" (point at `snapshot_ui`
for live state, the harness for byte proofs) and its tool list, `tools/proof/README.md`. The
tool counts that say "eighty-five" count product tools; say so rather than moving them.

## Record

Each phase's record goes here as it lands: what was built, what was measured, what the review
found, what is owed.

### V0 — the build flag and `make dist` (2026-09-26)

**Built.** `project.yml` declares Debug, Release and Distribution (a `release`-type copy of
Release: every target setting stays in `base:`), and sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS:
"$(inherited) REELCUT_DEV_TOOLS"` for Debug and Release only; the scheme's Archive action is
pinned to Distribution, Run stays Release. `app/Sources/AgentServer+DevTools.swift` (82 lines) is
the seam: `withDevHandlers(_:)` merges the dev handler table into the product one, and
`#if REELCUT_DEV_TOOLS` holds `devToolsMarker`, an empty `devHandlers`, an empty
`devOffMainTools` and a `devTools()` returning no rows; `#else` holds the same tables and a
`devTools()` returning `[]`. `AgentServer.swift` (frozen) took wiring only: the handler literal
renamed `productHandlers` with `handlers = withDevHandlers(productHandlers)`, the off-main set
renamed `productOffMainTools` (now `private`) with `offMainTools =
productOffMainTools.union(devOffMainTools)` — 797 → 801 lines. `AgentCatalog.swift` splices
`catalog += devTools()` (534 → 537). `make dist` builds Distribution with `-derivedDataPath build`
into `build/Build/Products/Distribution/` and runs `tools/proof/dist_check.py` (D1–D5).
`make typecheck` and `tools/proof/harness/build.sh` pass `-D REELCUT_DEV_TOOLS`; `build.sh`
now counts its own mtime in the staleness check.

**Measured.**
- `make typecheck` (flag on): 0 errors, 7 warnings — the baseline. The spec's
  `grep -c " warning: "` prints 14 because each warning is printed twice (the header line and
  the snippet's caret line); the header lines, `^app/.*: warning: `, number 7. The flag-off
  `swiftc -typecheck` (no `-D`): 0 errors, the same 7 (14 by the raw grep).
- `harness/build.sh`: built in 105 s, exit 0; the second call printed the path only.
- `make app`: exit 0. `make dist`: exit 0, `dist_check: 5/5`; the marker occurs once in
  Release's binary and 0 times in Distribution's (`LC_ALL=C grep -c -a -F`).
- `xcodebuild -list`: Debug, Distribution, Release. The scheme: ArchiveAction Distribution,
  LaunchAction Release. The pbxproj holds `REELCUT_DEV_TOOLS` twice, in the target's Debug and
  Release configurations only.
- Hand mutants of the check, each exit 1: `--release` = the Distribution app → D4 FAIL (4/5);
  `--dist` = the Release app → D5 FAIL (4/5); a missing Release → D2, D4 FAIL (3/5); a missing
  Distribution → D3, D5 FAIL (3/5); a trailing `// note`, a 12-byte marker, a second
  declaration → D1, D4, D5 FAIL (2/5) each. The build mutant — `Distribution:
  {SWIFT_ACTIVE_COMPILATION_CONDITIONS: REELCUT_DEV_TOOLS}` under the target's
  `settings.configs` — `make dist` exit 2, D5 FAIL (4/5); `project.yml` restored (`cmp`
  identical) and `make dist` 5/5 again.
- Both apps launched on their own ports (Release 4851, Distribution 4852): each logged
  `listening on`, `grep "Reelcut: "` printed nothing, `tools/list` held 85 tools. Release's log
  holds the line `Reelcut agent server: reelcut-dev-tools-compiled-in, 0 dev tools` once;
  Distribution's holds it 0 times.

**Deviations from this road map's V0 text.**
- The check greps a MARKER, not the dev tools' names. Swift string literals of 15 UTF-8 bytes or
  fewer are stored inline in the code of an `-O` binary: `RC_AGENT_PORT` (13) and
  `unsaved_changes` (15) are found 0 times in the Release binary, `AgentServerEnabled` (18)
  once, so `snapshot_ui` (11) could never be a needle. `devToolsMarker` is 29 bytes and is kept
  live by the log in the flag-on `devTools()`; V2 adds rows and handlers with no edit to the
  check.
- The dev rows are spliced BEFORE `fileTools`, not appended: `recording_probe.py` asserts the
  last eleven names are the file group plus `record_screen`.

**Also.** Xcode's Product ▸ Archive is pinned to Distribution, so an archive never ships the
flag. A dev tool reusing a product tool's name keeps the product handler and complains as the
parity check does (`assertionFailure`, then `NSLog("Reelcut: …")`), so a proof's
`grep "Reelcut: "` sees it.

**Review.** litecode (triage, design, adversary, final design, implement, review): the
adversary's two objections — a `git status` rule the uncommitted §11 files could not meet, and a
marker line whose trailing comment failed its own regex — were taken into the spec before code.
The review passed with no blocker or should-fix; its two nits were applied by hand afterwards
(`productHandlers` spelled `[String: ToolHandler]`, under 100 columns; the harness staleness
sentence in `tools/proof/README.md`), and so were root `CLAUDE.md`'s `make dist` and
`typecheck` lines and `app/CLAUDE.md`'s map entry for `AgentServer+DevTools.swift`.

**Owed.**
- V2: two probes — the tool count and the catalog order (dev rows before the file group) once
  the tables are not empty.

### V1 — spike: the preview well and the sheets (2026-09-26)

**Built.** `tools/proof/capture_spike/` (untracked output under `work/capture_spike/`): a
runner (`capture_spike.py`), a row table with one predicate per row (`rows.py`), the Q2(c)
inventory and its checker (`inventory.json`, `inventory.py`), and a probe compiled from the
whole of `app/Sources` but `main.swift` with `-O -wmo -D REELCUT_DEV_TOOLS` — the view classes
the app ships, optimised as Release is — in six modes (`well`, `sheets`, `modal`, `menu`,
`appearance`, `layout`), each a bounded child in its own process group. No dev tool was added:
nothing under `app/`, `core/`, `graphic/`, the build or `tools/proof/harness/` changed. The
probe runs `.regular` and `finishLaunching`, opens a package as the app does
(`makeWindowControllers`, `showWindows`, `orderFrontRegardless`, 1440 × 862), puts every
window it opens on the host's first scale-2 screen (`ProbeSupport.place`, after
`setContentSize` and before `showWindows`; a no-op when there is none) and, in `sheets`
and `appearance`, activates (`NSApp.activate()`, `makeKeyAndOrderFront`, a ≤ 3 s poll).

**Measured.** Host: macOS 26.5.1 (25F80), Mac14,6, console not locked, two screens (the built-in at scale 2, where every windowed mode ran, and
an external one at scale 1),
system appearance darkAqua. The probe built in 91 s (`-O -wmo`, exit 0) in the first run after
the probe's waits began dispatching events (below); the two runs this record quotes reused that
binary (B0 "up to date"), and a cached build writes `seconds: 0.0` into `answers.json`. The two
runs printed the same scores — `33 pass, 5 fail, 0 skip of 38` — the same digest
`3a35537e80bb6e952b426b9d87e57cb8abe309efcba3671e6133d12a255d8587`, and exit 0; they differ
only in timings. Mode seconds (`answers.json`'s `mode_seconds`), run 1 / run 2: layout
3.98 / 3.92, well 6.94 / 6.96, sheets 7.14 / 7.16, modal 2.14 / 2.14, menu 0.09 / 0.09,
appearance 12.26 / 12.33. The window facts (`answers.json`'s `windows`) read visible and not
occluded for `layout`, `well`, `sheets` and `appearance`; the probe activated in 4 / 6 ms in
`sheets` and 1 / 3 ms in `appearance`, the editor key both times.

- **An earlier run skipped 25 rows** — every W, S0–S3 and A row, `host: window occluded`, with
  activation not taking within 3 s — because the probe's waits turned `RunLoop.main.run`,
  which never dispatches AppKit events. With `ProbeSupport.pump()` (each event dequeued and
  handed to `sendEvent`) in `spin`, the activation poll and the occlusion wait, no row skips.
  Nothing that run measured is quoted here.
- **The placed probe.** The digest above and the W, S and A numbers below were first measured
  by the probe BEFORE `ProbeSupport.place` was added. The placed probe's first two runs
  (digest `c435f0f1…b3d7cc`, `12 pass, 1 fail, 25 skip of 38`) put every window at scale 2
  (`scale2_screens 1`, `screens 2`) but skipped every W, S0–S3 and A row as `host: window
  occluded` — a plain window on either screen read occluded too — so they scored none of
  those rows. Its next two runs (B0 "up to date", the same binary) scored every row: `33 pass,
  5 fail, 0 skip of 38`, the same digest `3a35537e…d8587`, exit 0, every windowed mode at
  scale 2, not occluded, and active in `sheets` and `appearance`. The build seconds, mode
  seconds and activation times in the paragraph above are the pre-placement probe's too.
- **B0** pass. **W0** pass: visible, not occluded, scale 2, `displayedPixelBuffer()` non-nil
  after 0 ms. **W1** pass — the live well captures as the canvas BACKGROUND, not the picture
  and not black: mean [234, 51, 247], 1 401 782 magenta pixels, 0 black, 0 yellow in the shape's
  rect; the never-shown window (the harness's case) the same, mean [233, 51, 246]. **W2**
  (control) pass: M 19 678 px, M-core 9 124, M dilated 30 302, reselected capture identical.
  **W3** (control) pass: the still 4/4, the unmodified well 1/4.
- **W4a, W4b, W4c fail — on (ii) alone, and with the same numbers**: (i) 4/4 quadrants;
  (ii) 8 296 of 9 124 M-core pixels (0.9093) within 3/255 of the unmodified capture, against a
  bar of 0.99; (iii) 0 pixels changed outside the well ∪ M-dilated; (iv) tree restored, next
  capture identical (0 px). **W5** (control, the image above the overlay) pass: (ii) falls to
  325 / 9 124 (0.0356). **W6** (control, the image left in) pass: (ii) 0.9093 again, (iv)
  fails — the next capture differs by 1 412 918 px. W4c's overlay capture is alpha 0 over
  0.9916 of its pixels. W4a's `overlay_alpha` (added to the probe after the two runs above, and
  printed by a later run with the same scores and digest, at scale 2): the overlay's
  alpha at each M-core pixel, solved from `selected`/`unselected` (overlay over the background)
  and `w4a`/`w5` (overlay over the picture, the picture alone), is 0.985–1 (median 1) at the
  8 296 kept pixels and 0.897–0.974 (median 0.902) at the 828 others, 0 without contrast — a
  translucent part of the overlay, through which the picture shows as it does on screen. The
  run after it put the window on an external screen at scale 1: M-core 302, and W4a–W4c kept
  302 / 302 (alpha 1–1), so they passed and the digest differed (`36 pass, 2 fail`).
- **S0** pass: 11 menus, the three items found, each targeting `EditorViewController`; active,
  key and main. **S1a, S1b, S1c** pass, route 1 (`performActionForItem`) every time: Export…
  returned in 362 / 376 ms, Remove Track 295 / 303 ms, Add Media… 761 / 749 ms, each with its
  sheet (`NSWindow`, `_NSAlertPanel`, `NSOpenPanel`) attached at the return, the marker unrun and
  `NSApp.modalWindow` nil. **S2a** pass: the Export sheet 840 × 1342 px (bounds × scale), 416
  colours, closed by `dismiss` in 267 / 269 ms. **S2b** pass: the alert 520 × 276 px, 461
  colours, closed by `endSheet` in 268 / 264 ms. **S2c fail**: the open panel is the right size,
  1760 × 896 px, but ONE colour — its content view is an `NSRemoteView` with 0 subviews; it
  closed by `endSheet` in 271 / 266 ms. **S3** (control) pass: the parent's capture matches the
  sheet at 0.1122, 0 and 0.0032 of the sheet's rect. **S4** (control) pass: a menu item whose
  action is `NSAlert().runModal()` returned after 1.024 / 1.023 s (aborted by a `.modalPanel`
  timer at 1.0 s); a `main.async` marker enqueued before it ran INSIDE the call; a background
  thread's `DispatchQueue.main.sync` at 0.3 s completed at 300 / 301 ms, inside the call.
- **I1–I3** pass, **I4** (control) pass: 145 menu leaves, 93 live selectors, 93 inventory rows,
  0 problems; 41 grep sites — `beginSheetModal` 25, `presentAsSheet` 8, `runModal` 6, `popUp`
  2 — one-to-one with the inventory, 0 problems; verdicts framework 16, modal 1, none 55, sheet
  15, window 6, 0 problems; the checker over a copy without `addActionAtPlayhead:` and
  `app/Sources/AppDelegate.swift:121` reported exactly those two.
- **A0** pass: on screen, system and effective darkAqua, active, key. **A1** (control) pass: a
  fresh aqua and a fresh darkAqua window differ at 3 174 278 px (0.6393). **A2** (control) pass:
  two fresh windows of one appearance, byte-identical. **A3–A6** pass, each byte-identical (0
  px): `window.appearance` set to the opposite (aqua) = a fresh aqua window; set back to nil =
  the capture before; the same two through `window.contentView?.appearance`. **A7** (control)
  pass: darkAqua set explicitly = the nil capture.
- **L1** pass (a view pinned leading, top, width: `hasAmbiguousLayout` true, frame height 0);
  **L2** pass (height pinned too: false). **L3** fail — 3 of 401 views in the editor (the
  note fixture, its text clip selected, the Text sub-tab) answer ambiguous:
  `_NSTextSelectionView`, `_NSTextRenderingSurfacesGroupView`, `_NSTextContentView`, all at
  [1160, 531, 236, 72] in window points — AppKit's private subviews of the inspector's text
  view. **L4** pass (truncating label: intrinsic 430.5 vs frame 120); **L5** pass (22 vs 200);
  **L6** pass (wrapping label, `preferredMaxLayoutWidth` 120: intrinsic 120 vs frame 120, not
  truncated). **L7** pass — #70 reproduced: the Reveal section's `InspectorNoteLabel` reading
  `TextPane.wordStyleNote` measures intrinsic 289.5 against a frame of 271, and it is the only
  visible text field in the tree wider than its frame.

**Answers.**
- **Q1 — the picture goes UNDER the canvas overlay, put in for the capture and taken out
  after.** `cacheDisplay` of the live well gives the canvas background, not the picture (W1).
  All three under-techniques — (a) an `NSImageView` positioned above `playerHost`, (b) a
  `CALayer` with the image above the `AVPlayerLayer` in `playerHost.layer`, (c) three passes
  (the capture, the image into the well rect, `overlay`'s own `cacheDisplay` drawn over) —
  put the picture in every quadrant, change nothing outside the well, and leave the tree and
  the next capture as they were; they measured alike on every count, so the spike does not
  choose between them. Under keeps 0.9093 of the overlay's core pixels where over keeps 0.0356
  (W4 against W5); the 828 it does not keep are the overlay's pixels of alpha 0.897–0.974
  blending with the picture as they do on screen (W4a's `overlay_alpha`, above; at scale 1 the
  core held none and all three passed), so the 0.99 bar in (ii) — written for an opaque
  overlay — is the part that failed, not the technique. The image must come out
  again: left in, the next capture differs by 1 412 918 px (W6).
- **Q2(a) — sheets are captured by their own content view, except the file panels.** The
  Export sheet and an `NSAlert` sheet capture at bounds × scale with 416 and 461 colours (S2a,
  S2b), and the parent's capture does not hold them (S3). The `NSOpenPanel` sheet captures as
  one colour: its content is an `NSRemoteView` drawn out of process (S2c). `NSSavePanel` was
  not measured.
- **Q2(b) — a menu item puts its sheet up without blocking the main thread.**
  `performActionForItem` returned with the sheet attached, no modal window and the main queue
  not run inside the call, for all three items (S1a–S1c); `dismiss` and `endSheet` close them
  within 3 s (S2). A `runModal` is the opposite (S4): reached from a menu action it services the
  main queue inside itself, so the agent server's `DispatchQueue.main.sync` hop
  (`AgentServer.swift:792-798`) does not deadlock against it — it runs re-entrantly INSIDE the
  loop, while the call that started the loop does not return; and the server reads one request
  at a time (`core/src/agent.rs:89-90`), so no later request is read until the modal ends. A
  modal item therefore wedges the agent for as long as it is up, which is why V2 refuses them.
- **Q2(c) — the inventory: answered.** One selector is `modal`: `toggleAgentServer:` (Tools ▸
  Allow Agent Connections), whose failure path is `NSAlert.runModal` inside the call
  (`AppDelegate.swift:212`, gated on `AgentServer.start()` throwing, `:206`). Sixteen are
  `framework` — AppKit's own implementations, read and not run: `hide:`,
  `hideOtherApplications:`, `unhideAllApplications:`, `terminate:`, `openDocument:`,
  `clearRecentDocuments:`, `performClose:`, `saveDocument:`, `saveDocumentAs:`,
  `revertDocumentToSaved:`, `undo:`, `redo:`, `performMiniaturize:`, `performZoom:`,
  `arrangeInFront:`, `showHelp:`. Fifteen put up a `sheet` inside the call, six open a
  `window`, 55 do neither. The rows with a `reached_after` column — a modal or sheet site the
  item reaches only later — and what V2's refusal does with each:

  | Menu item (selector, verdict) | Reaches later | via | gate | V2 |
  |---|---|---|---|---|
  | Quit (`terminate:`, framework) | `runModal` `AppDelegate.swift:121` | `applicationShouldTerminate` `:90` | export queue not idle `:108` | refused (framework) |
  | Open… (`openDocument:`, framework) | relink sheet `+Export.swift:121`; ffmpeg consent `runModal` `FFmpegRewrap.swift:473`; reverse sheet `ProjectDocument.swift:930`; relink Locate… panel `RelinkSheetController.swift:123` | `EditorViewController.swift:296`; `ProjectDocument.swift:592`; `:455`; `RelinkSheetController.swift:254` | missing media `+Export.swift:118`; `FFmpegRewrap.swift:510`; unrendered reverse `ProjectDocument.swift:919` | refused (framework) |
  | Add Media… (`addMediaFiles:`, sheet) | ffmpeg consent `runModal` `FFmpegRewrap.swift:473` | the panel's completion `EditorViewController.swift:655` → `MediaImporter.swift:102` | policy `ask` and `canAsk` `FFmpegRewrap.swift:510`, false while the agent server is enabled (`:74-76`) | allowed: a dev tool never chooses a file, and under the agent `canAsk` is false |
  | Export… (`exportProject:`, sheet) | preset name `runModal` `ExportSheetPresets.swift:289`; save panel sheet `ExportSheetController.swift:582`; progress sheet `+Export.swift:56` | the sheet's Save… `ExportSheetPresets.swift:149`; Export… `ExportSheetController.swift:522`; save panel completion `:591` | a resolved card `:180`, `:552`; Export… not Add to Queue `:588` | allowed: V2 opens the sheet and never presses a button in it |
  | Speed… (`showSpeedSheet:`, sheet); Undo, Redo (framework); Paste (`paste:`, none) | reverse progress sheet `ProjectDocument.swift:930` | `ProjectDocument.swift:1265` | unrendered reverse `:919` | Speed… and Paste allowed — a sheet, not a modal, but it can arrive a run-loop turn after the item returns; Undo, Redo refused (framework; `undo`/`redo` are tools already) |
  | Import Captions…, Export Captions…, Save Frame…, Add Font / Image to Graphics…, Insert ▸ Graphic ▸ From File…, Clip ▸ Add Background ▸ Image… (sheet) | alert sheets on failure or report | the panel's completion or an async hop (the table's `via`) | the failure | allowed: sheets |

  Sites no menu item reaches (their `other_caller`): `GraphicPane+Source.swift:200, 205`
  (`runModal`, the Graphic sub-tab's Duplicate as New Graphic), `OptionControls.swift:178, 401`
  (`popUp`, inspector controls' mouse-down), `MediaPaneCommands.swift:181, 237` (Media tab row
  menu), `PreviewCanvasView+TextEditKeys.swift:56` (Escape in the canvas text editor).
- **Q3 — appearance switches live.** Setting a live window's `window.appearance` (or its
  content view's) to the opposite gives the same bytes as a fresh window built with it, and
  setting it back to nil gives the bytes from before (A3–A6, 0 px each, against A1's 63.9 %
  and A2/A7's identities). The colours taken once as `CGColor`s left no residue in this
  editor state. V2's `appearance` argument sets `window.appearance`, captures, and restores
  it; no fresh window is needed.
- **Q4 — the layout signals in an `-O` build: answered.** `hasAmbiguousLayout` answers
  truthfully in the `-O -wmo` build against a deliberate ambiguity and its control (L1, L2).
  The editor's own tree is NOT clean: three private AppKit views inside the Text sub-tab's text
  view answer ambiguous (L3), so a `problems` list that takes every view would never be empty
  and V2's "empty without the mutant" proof would fail — V2 lists `_NS…` views apart.
  "Intrinsic width > frame width" separates a truncating label from one that fits (L4, L5),
  does not flag a wrapping label (L6), and finds #70 (L7: 289.5 > 271).

**Review.** litecode, full route with five fix passes, the cap. Pass 1 found the probe's waits
never dispatched events, which is why the first run skipped 25 rows; passes 2, 3 and 5
rewrote this record from printed numbers (pass 3 moved the overlay-alpha solve into the probe);
pass 4 placed the windows on a scale-2 screen after a run on a scale-1 screen changed the
digest. The last review passed with five nits, applied by hand afterwards: the wording at
"one screen" and "in every render", "five `probe_*.swift`", the missing Deviations, and the
three bare waits entered under Owed rather than changed without a rerun. The V2 bullet on
driving an inactive, occluded app was added by hand at the same time.

**Changes to V2's text.** (1) The layout dump's `problems` list takes `hasAmbiguousLayout`
views except AppKit's private `_NS…` subviews, which it lists apart (from L3). (2)
`perform_menu_item` refuses by name the items the inventory reads `modal` (Tools ▸ Allow Agent
Connections) or `framework` (the sixteen AppKit-owned items), not "any item V1 found to run a
modal loop" in general (from Q2(c)), and says what S1 measured of delivery. (3) `fill_preview`
keeps its default of true and names its technique: the picture under the canvas overlay for the
capture, removed after (from Q1). (4) `snapshot_ui`'s `sheet` says a file panel captures as one
colour and reports it rather than returning a flat picture (from S2c). (5) `appearance` sets the
live window's appearance and restores it after (from Q3). (6) The proof's unfilled well is the
canvas background, not black (from W1), and its sheet is an app sheet (from S2c).

**Deviations.**
- The road map's "34 sheet sites" is 33 call lines (25 `beginSheetModal`, 8 `presentAsSheet`)
  plus the doc comment at `AppDelegate.swift:64`; none of them calls `runModal`. The six
  `runModal` lines are elsewhere: `AppDelegate.swift:121, 212`, `ExportSheetPresets.swift:289`,
  `FFmpegRewrap.swift:473`, `GraphicPane+Source.swift:200, 205`.
- The site grep does not count the app-modal `NSApp.presentError(_:)` / `presentError(_:)`
  (the sheet form `presentError(_:modalFor:…)` is not modal): `AppDelegate.swift:170` (New
  Project's failure path), `EditorViewController.swift:415` (a failed player rebuild),
  `FileDropView.swift:52` (a dropped file that will not open), `ProjectDocument.swift:1332` (a
  document with no window), `WelcomeWindowController.swift:189`. `newProject:` is read `window`
  on its success path; its failure path is modal.
- The probe calls `orderFrontRegardless` after `showWindows` in every mode (the spec's
  activation step is `sheets`' and `appearance`'s only), so every mode's window is ordered
  front whether or not the probe activates.
- B0 is scored in every run whatever `--only` says, because the build runs in every run.
- The probe pins the spec's defaults plus `ReelcutInspectorCollapsed`, `ReelcutSnappingEnabled`,
  `ReelcutInspectorRescaleClips`, `ReelcutExportChoice` and `AgentServerEnabled` (false), a
  subset of `harness/main.swift`'s keys; it does not copy the harness's removal of persisted
  `ReelcutInspectorSection.*` keys.
- L7 scrolls the note into view (`scrollToVisible`) before checking `visibleRect`, so "on
  screen" means inside the inspector's visible scroll area.
- `answers.json` carries two keys the spec did not list, `windows` and `mode_seconds`, and W4a's
  `measured` carries `overlay_alpha` (added by review pass 3, so Q1's cause is a printed number).
- W4a–W4c depend on the window's scale (at scale 1 the M-core is ~300 px and they pass), so
  the probe places every window on the first scale-2 screen (`ProbeSupport.place`). Two rules
  the spec did not list come with it: a named skip, `host: no scale-2 screen`, for W4a–W4c
  when the host has none (`rows.py`); and W4a–W4c FAIL, naming both numbers, when a scale-2
  screen exists but the window's scale is not 2 (`capture_spike.py`'s `score`), since that is
  a placement fault rather than host state.

**Owed.**
- `CLAUDE.md` lines. Root `CLAUDE.md`'s "Seeing the chrome" says "The preview well comes out
  black (a Metal layer has no drawable offscreen), so nothing about the PICTURE is ever claimed
  offscreen". W1 measured the well as the canvas background colour, in the live window and in
  a never-shown one alike (magenta in the fixture); it is black only when the project's
  background is. At the road map's close the line reads: "The preview well comes out as the
  canvas background (an `AVPlayerLayer` or Metal layer does not draw into `cacheDisplay`), so
  nothing about the PICTURE is ever claimed offscreen". No `CLAUDE.md` line changes on Q2–Q4.
- Three waits in the probe still turn a bare `RunLoop.main.run` rather than
  `ProbeSupport.pump()`: `probe_sheets.swift:160, 185` and `probe_well.swift:132`. They scored
  their rows in the passing runs; change them only together with a rerun of the spike.
- Defects to file at the road map's close: #70 is reproduced by L7 (intrinsic 289.5 > frame
  271); `newProject:`'s app-modal `NSApp.presentError` (`AppDelegate.swift:170`) is outside V2's
  refusal list unless the grep grows a `presentError(` token.

### V2a — `snapshot_ui` and its layout dump (2026-09-26)

**Built.** `snapshot_ui`, the first dev tool.

The app side, every new file wholly under `#if REELCUT_DEV_TOOLS`:
- `app/Sources/AgentServer+Snapshot.swift` (398 lines): the handler, argument reading, the
  catalog row and the result.
- `UISnapshot.swift` (216): window resolution, regions, facts, staging and one capture pass.
- `UISnapshotLayout.swift` (160): the view walk and its three rules.
- `AgentServer+DevTools.swift`'s flag-on tables name the tool, its handler and its off-main
  membership (85 lines).
- `AgentServer.swift` and `AgentCatalog.swift` are untouched.

The proof side:
- `tools/proof/dev_tools.py`: `DEV_TOOLS` and the marker count.
- `v2_snapshot.py`: 29 rows.
- `v2_layout_probe.swift`: P1–P6.
- `v2_cover.swift`: an opaque, non-activating floating panel that occludes the editor.
- `op_argument_proof.py`: `PRODUCT_TOOLS = 85`, the dev tools counted apart, and V0's owed
  count and order rows.
- `recording_proof.py` and `phase9_proof.py`: their app-state set subtracts `DEV_TOOLS`.

**Measured.** Host: console not locked; two screens. The editor opened on the external
BenQ GW2790QT at scale 1, frame [2536, 701, 944, 736], content 944 × 704. The width is the
fixture's own: canvas 640 + inspector 304 (`EditorWindowController.swift:21-24`).
- `make typecheck`: 0 errors, 7 unique warnings. `make app` exit 0. `make dist` exit 0,
  `dist_check: 5/5`. `grep "Reelcut: "` printed nothing on every launch.
- **Occlusion was measured first** (step 2), with `--only T,N,O`: 8/8 pass.
  - The cover made the listing read `occluded: true`.
  - Covered captures were byte-identical, settled in 2 passes, at 944 × 704 px.
  - A covered capture was byte-identical to an uncovered one.
  - `set_selection [3]` while covered changed only the inspector and timeline regions.
  - The app was inactive for every capture.
  - Each cover episode lasted 0.5–0.9 s.
- **Step 5 stopped on L2**: one problem, which the orchestrator filed as #129 (below). L2
  now compares `problems` to `KNOWN` in `v2_snapshot.py`.
- **Final runs**: two fresh instances on port 4861, each `29 pass, 0 fail, 0 skip of 29`,
  digest `c53b8d741e9f0f3e288439cb51c21cf4f7c8a2d74817c6c08cb970e329a018cc`, exit 0. The row
  values quoted below come from the full runs; they were the same in every run shown.
  - The very first full run had the same scores and digest, but used F3's earlier form
    (without the baseline) and F0's earlier bound.
  - Two intermediate runs scored `28 pass, 0 fail, 1 skip`, digest `3ee9cf1c…ebbd9`. O2
    skipped as `host: editor occluded without the cover (occluded before True, after True)`:
    the person's windows were over the editor.
- Row values:
  - C1: 42 902-byte PNGs, byte-identical.
  - C3: toolbar 944×44, preview 639×359, inspector 304×359, timeline 944×300 px, each equal
    to its region rect × scale.
  - C4: 15 of 15 refusals name their argument or window.
  - C5: Welcome was open and captured at 720×600 px; Settings was closed and refused by name.
  - F0 (covered): the box [288, 151, 352, 186] px was [252, 254, 48] filled and
    [254, 25, 251] unfilled.
  - F2: M = 3 820 px, all of which also differ when filled (1.0000).
  - F1, F3, F4, A1 and A2 pass.
  - L1: 84 views.
  - L2: #129 matched, 0 not known.
  - L3: the note is intrinsic 290 against frame 271, listed `truncated` (#70).
  - P1–P6 pass. In P4 the wrapping label is intrinsic 349.5 against frame 120, so the
    wrapping exemption is exercised.
- **#129 does not depend on the window's width or screen.** A scratch probe (V1's
  `probe_support.swift` over v2well, not kept) ran `UISnapshotLayout.report` at content
  widths 900, 944, 960, 1024, 1200 and 1440 pt, on the scale-2 built-in screen and on the
  scale-1 external screen. Every one of those twelve reports held exactly #129: frame
  [367, 15, 90, 14], overhang [0, 0, 2, 0].
  - At 800 pt, below the window's 900 pt `minSize` (`EditorWindowController.swift:15`), 21
    ambiguous views in the timeline's tool bar and a 17 pt stack overhang appear as well.
    That width is unreachable, so they are not filed.
- **F0 and colour management.** Captures are in the window's colour space: the PNG carries
  the display's profile, where `render_frame`'s carries sRGB IEC61966-2.1. A scratch probe
  staged the app's own `render_frame` picture with `UISnapshot.stage` on the built-in
  "Color LCD" screen at scale 2, then captured with `UISnapshot.pass`:
  - filled: [255, 255, 84];
  - unfilled: [234, 51, 247], matching V1's W1.

  The spec's yellow bound (B < 60) fails there on colour management alone, so F0's bound is
  B < 100. The BenQ gives 48.
- **Mutants**, each run on a fresh instance or a rebuilt probe, and each file restored
  (`cmp` against a saved copy, since the files are untracked):
  - **M1**, the fill `.above` the overlay: F2 fails, 0 of 3 820 (0.0000); the other F rows
    pass.
  - **M2**, `unstage` leaves the fill: F3 fails, byte-identical to the one just before but
    NOT to the run's first capture. F0 also fails: its unfilled box is yellow, 2 240 px not
    magenta, because its unfilled capture follows its filled one.
  - **M3**, the appearance not restored: A2 fails (dark → light); A1 passes.
  - **M4**, `isPrivate` always false: P3 fails, `_NSV2ProbeView` in `problems`.
  - **M5**, the wrapping exemption removed: P4 fails, the wrapping label #5 flagged.
- **The three older proofs**, each on a fresh instance:
  - `op_argument_proof.py`: 147/147. This includes 85 product tools, `['snapshot_ui']`
    present with marker count 1, the dev tools immediately before `import_media`, and 27
    tools that are not ops (26 product and 1 dev).
  - `recording_proof.py`: 187/187 at implementation, with the known 2-check
    Bluetooth-output skip; the edited app-state row passes. After the pass-1 review fix (a
    change to where `snapshot_ui` reads a view's bounds, which recording never calls), a
    fresh-instance run on the dev-tools Release build scored 186/187: the edited app-state
    row passes, and one microphone-length row fails ("the microphone file is not SHORTER
    than the movie by more than two frames": microphone 1201600 vs movie 1280000 ticks, a
    residual of -38.5 ms of tail). A control on the Distribution build, which has none of
    this phase's code, scored 178/183: the answer carried no `mic_clip`, and five
    microphone rows failed. The failures are put down to host microphone state (the
    default input and output were AirPods), not to this phase; that is not confirmed.
  - `phase9_proof.py`: 216/218. The edited app-state row passes. The two failures are
    nest-scope playhead rows ("maps the playhead in by the nest clip's start", "with the
    playhead mapped back out"). The same rows fail on both builds. "With the playhead mapped
    back out" failed on every run of either build; "maps the playhead in" and two more rows,
    "the playhead reads 1 in here where the timeline's is 1200000" and "leaving maps the
    playhead back OUT (600000)", fail on some runs and not others. Filed as #130. Five fresh-instance runs after
    review showed this. On the dev-tools Release build: 215/218 ("mapped back out", "maps
    in", "reads 1"), then 216/218 ("mapped back out", "maps in"). On the Distribution build,
    which has none of this phase's code: 216/218 ("mapped back out", "maps in"), 216/218
    ("mapped back out", "leaving"), then 215/218 ("mapped back out", "reads 1", "leaving").
    The first control scored 217/218, failing only "mapped back out". So the failures are
    not this phase's.

**Deviations from this road map's V2 text and the V2a spec.**
- `snapshot_ui` runs off main (`AgentServer+DevTools.swift`'s `devOffMainTools`), where
  the road map's V2 bullet says "main thread; not in `offMainTools`". The fill waits on
  `Exporter.renderFrameReported`, and the settle waits 20 ms between passes; every AppKit
  touch is an `onMain` hop (`AgentServer+Snapshot.swift`).
- The layout dump's `frame` is in capture points with a top-left origin
  (`UISnapshot.rect`), not window points. For an editor capture, the result's `origin`
  gives the captured root's rect in window-content points.
- Problems on AppKit's private `_NS…` views of EVERY kind (not only ambiguity) go to
  `private_problems` (`UISnapshotLayout.report`).
- The ambiguous-constraint mutant is the probe's (P1, a synthetic tree), not one in the
  running app.
- The `set_selection` row runs covered (O3).
- L2 is "`problems` equals the filed defects in `KNOWN`" rather than "empty". This was the
  user's decision after the step-5 STOP.
- F0's yellow bound is B < 100, not < 60 (colour management, above).
- F3 also compares against the run's first capture, taken before any fill: without that
  baseline, M2 passes F3.
- M2 fails F0 as well as F3 (above). The spec's "exactly its row" does not hold for it,
  because any unfilled capture after a filled one shows the leftover picture.
- `project` is refused with `welcome` as well as `settings`. `openWindow` counts only a
  visible window, which matches the listing.
- C4 exercises 15 refusals. It cannot reach two over MCP in V2a: a windowless document, and
  a file-panel sheet.

**Review.** litecode, full route, two fix passes. The adversary's three objections (F0's
sample box on the shape's edge, L3's missing-label case, L2 against the pass rule) were taken
into the spec before code. Implementation stopped once at L2, as the spec required: the tool's
first run over a clean editor found the toolbar's duration label 2 pt past its stack view. The
user chose to file it (#129) and have L2 expect the filed defects by issue number. Pass 1
moved the last AppKit read (`bounds.size`) into an `onMain` hop and split the nest-playhead
rows by build and run; pass 2 corrected the record's `recording_proof.py` figures. The last
review passed with four nits, applied by hand: this paragraph, the nest rows' double count
(now #130), `op_argument_proof.py`'s dev-tool index guarded against a missing first tool, and
L3's "inspector wide enough" skip given the truncation rule's 0.5 pt tolerance
(`py_compile` only; neither proof was re-run for these two lines).

**Owed.**
- kpgalligan/reelcut#129: the toolbar's duration label runs 2 pt past its stack view. It is
  filed, and L2 lists it in `KNOWN`; when it is fixed, L2 fails until the entry is removed.
- `phase9_proof.py`'s nest-scope playhead rows fail on the dev-tools build and on the
  Distribution build alike (the results above). "With the playhead mapped back out" fails
  on every run, and three others fail on some runs. They are not this phase's; filed as
  #130.
- `recording_proof.py`'s microphone rows failed after review on both builds (186/187 on
  the dev-tools build, 178/183 on the Distribution control; the results above). The cause
  is thought to be host microphone state (AirPods as the default input) but is
  unexplained; a rerun with a built-in or wired input is owed. Not filed.
- V2b: `perform_menu_item`, sheet capture through it, and the file-panel refusal proved
  over MCP.

### V2b — `perform_menu_item`, `cancel_sheet` and sheet capture through them (2026-09-27)

**Built.** Two dev tools, every new app line under `#if REELCUT_DEV_TOOLS`.
- `perform_menu_item {path?}` runs a main-menu item by its titles, delivered to the NAMED
  project window's own responder chain, answered after a bounded settle; with no `path` it
  lists every leaf (path, selector, verdict, refusal, enabled, state, hidden).
- `cancel_sheet {}` closes the sheet attached to a project's window through its own Cancel: a
  file panel by `endSheet(_:returnCode: .cancel)` on its parent, else the button whose key
  is Escape, else a lone button; anything else is refused with the buttons' titles.

The app side:
- `app/Sources/AgentServer+MenuItem.swift` (314 lines): both handlers, argument reading, the
  window, the settle loop (`UISheet.pollInterval` 20 ms, 5 equal reads, bound 3 s), the
  results and both catalog rows.
- `UIMenu.swift` (224): the leaf walk, the path lookup (each level validated before its titles
  are read), the refusal, the responder walk, validation (`validateMenuItem`, else
  `validateUserInterfaceItem`; `isEnabled` is never written) and the perform, inside one
  explicit undo group on the window's document (`performGroupedEdit`'s discipline).
- `UIMenuTable.swift` (112): `UIMenu.verdicts`, one row per `inventory.json` selector, in
  its order (93).
- `UISheet.swift` (85): the settle fingerprint (attached sheet, `NSApp.modalWindow`, the
  sorted visible window numbers) and the Cancel search and press.
- `AgentServer+DevTools.swift` (89): the two handlers, `devOffMainTools` and the two catalog
  rows. `UISnapshot.swift`: `kind(of:)` and `row(_:)` lost `private`.
- `AgentServer.swift`, `AgentCatalog.swift` and `AgentServer+Snapshot.swift` are untouched.

The proof side:
- `tools/proof/capture_spike/inventory.py`: the site grep counts the app-modal
  `presentError(` (not `presentError(_:modalFor:…)`) as a loop token (V1's Owed).
- `inventory.json`: five `presentError` sites, and `newProject:` read `modal` (below).
- `dev_tools.py`: `DEV_TOOLS = ["snapshot_ui", "perform_menu_item", "cancel_sheet"]`.
- `v2_menu.py` (24 rows, T H N D U R S) and `v2_menu_probe.swift`.

**The inventory decision.** Of the five app-modal `presentError` sites only
`AppDelegate.swift:170`, New Project's failure path, is reached INSIDE a menu action, so
`newProject:` is `modal` and refused; the `new_project` tool is the capability.
`EditorViewController.swift:415` is `playback.onError`, reported asynchronously after any edit:
an app-modal started outside a call services the main queue (V1's S4) and holds no call open.
`FileDropView.swift:52` (a Finder drop), `WelcomeWindowController.swift:189` (the Recent
buttons) and `ProjectDocument.swift:1332` (`present(_:)` with no window, which
`perform_menu_item` cannot reach — it reaches editor actions only through a window) are
reached by no menu item. Of the six `runModal` lines, Quit (`:121`) and Allow Agent
Connections (`:212`) are refused; `ExportSheetPresets.swift:289` needs the Export sheet's
Save…, `FFmpegRewrap.swift:473` a chosen file, and `GraphicPane+Source.swift:200, 205` no menu
item — neither tool presses any of those.

**Measured.** Host: console not locked; the person's windows over the editors (V2a's O2
skipped on the same host, below).
- `make typecheck`: 0 errors, 7 unique warnings. `make app` exit 0. `make dist` exit 0,
  `dist_check: 5/5`. `grep "Reelcut: "` printed nothing on every launch; the startup log
  reads `reelcut-dev-tools-compiled-in, 3 dev tools`.
- **Delivery was measured first** (`--only T,D`, fresh instance on 4881): 7 pass, 0 fail,
  0 skip, digest `1e678078…62974`; the same after the script's last edit.
  - D0: the cover up over B's frame, B read `occluded: true`, the listing `active: false`.
  - D1: Add Marker to B went to `Reelcut.EditorViewController`; B markers +1, A +0;
    `active` false, B occluded; the action took 5–7 ms and the settle 124–136 ms over the
    runs.
  - D2: with no `project` the front project, A, was resolved; A +1, B +0, `active` false.
  - D3: Export… on B had its sheet (`NSWindow`) at the answer and A none; `snapshot_ui
    window: sheet` captured 420 × 671 px, equal to points × scale; `cancel_sheet` pressed
    `Cancel` (`cancel_button`) and no sheet was attached at its answer (settled in 129–143 ms).
  - D4: Settings… went to `Reelcut.AppDelegate`; `windows_opened` held one `settings` row,
    `active` false; `snapshot_ui window: settings` captured 460 × 340 px.
  - Each cover episode lasted 1.6–1.7 s.
- **Final runs**: two fresh instances on port 4881, each `24 pass, 0 fail, 0 skip of 24`,
  digest `91ac4a50f3154e1a383c540a7a06537b5640beb3bd2705b688976312fbedd011`, exit 0.
  - H1: 145 leaves, 93 live selectors, 93 rows, 46 grep sites (41 + the five
    `presentError`), 0 problems. H2: the table and the inventory agree both ways. H3: 18
    leaves refused, framework 16 and modal 2. H4: the fake leaf `v2Stranger:` alone, and the
    table without `addActionAtPlayhead:` alone, were reported.
  - N1: the live menu has 172 leaves and 104 live selectors. Unclassified, AppKit's:
    `_handleInsertFromContactsCommand:`, `_handleInsertFromCreditCardsCommand:`,
    `_handleInsertFromPasswordsCommand:`, `closeAll:`, `duplicateDocument:`, `moveDocument:`,
    `renameDocument:` ×1 each, `makeKeyAndOrderFront:` ×3, `orderFrontCharacterPalette:` ×3,
    `showWritingTools:` ×11, `startDictation:` ×2.
  - U1: two Add Markers +2, `undo` +1, `undo` +0.
  - R1–R6: the Undo item (retitled "Undo Add Marker") refused `framework` naming `undo:`;
    New Project refused `modal` naming `newProject:` with the editor count unchanged; Clear
    Range with no range refused `disabled`; an unknown item and menu refused listing
    `Export…` and `File`; Clip ▸ Transition refused `submenu`; `[]` refused; a Window-menu
    window item refused `unclassified` naming `makeKeyAndOrderFront:`.
  - S1: Export… on A, settled, captured 420 × 671 px with 250 and 387 colours (runs 1 and
    2); Add Marker refused `disabled` while it was up; cancelled with nothing changed. S2:
    Remove Track's alert (`_NSAlertPanel`) captured 260 × 138 px, cancelled by `Cancel`,
    tracks and clips unchanged. S3: Add Media… put up an `NSOpenPanel` (`file_panel` true);
    `snapshot_ui window: sheet` refused it as a file panel; `cancel_sheet` ended it
    (`end_sheet`), media unchanged. S4: `cancel_sheet` with none refused. S5: all 14 answers
    settled, 124–158 ms, no modal window.
- **Mutants**, each on a fresh instance (M1–M4 after `make app`), each file restored and
  `cmp`-checked against a saved copy:
  - **M1**, `refusal` answers nil for `framework`: H3 (framework 0 refused), N1 and R1 fail.
    R1's Undo was PERFORMED inside the perform's undo group and the app died:
    `NSInternalInconsistencyException`, "undo was called with too many nested undo groups";
    every later R and S row then failed on the lost connection.
  - **M2**, `sendAction(…, to: nil, …)`: D1 and D2 fail — nothing handled Add Marker with
    the app inactive (V1's S0) — and so does every later row that performs an editor item
    (D3, D4, U1, R1–R6, S1–S5), since the tool refuses an action nothing handled.
  - **M3**, no undo group: U1 alone fails — one undo took both markers, the second took
    D1's (+0, then −1).
  - **M4**, `isEnabled` always true: R3 (Clear Range performed) and S1 (Add Marker performed
    under the sheet) fail, and only those.
  - **M5**, `inventory.json`'s `newProject:` back to `window` (no rebuild): H1 (I3,
    "reaches presentError at app/Sources/AppDelegate.swift:170 synchronously but is not
    modal"), H2 and N1 fail, and only those.
- **The older proofs**, each on a fresh instance:
  - `v2_snapshot.py` (4882, V2a's launch line): `28 pass, 0 fail, 1 skip of 29`, digest
    `3ee9cf1c…ebbd9`, V2a's own digest for that skip — O2, `host: editor occluded without the
    cover`. A first run launched without `-ReelcutInspectorSection.text.animation '<false/>'`
    also skipped L3 (`host: Reveal collapsed`); that launch was not V2a's line.
  - `op_argument_proof.py`: 149/149 on Release (4883), 145/145 on Distribution (4884), the
    three dev tools all present with marker count 3 / all absent.

**Deviations from this road map's V2 text and the V2b spec.**
- Both tools run OFF main (`AgentServer+DevTools.swift:68`), as `snapshot_ui` does: the
  settle sleeps between reads, and every AppKit touch is an `onMain` hop.
- Delivery is the tool's own responder walk and `NSApp.sendAction(_:to:from:)` to the object
  found (`UIMenu.swift:123`, `:150`, `:207`), not `performActionForItem`, which is
  nil-targeted.
- The refusal list is an ALLOW-table (`UIMenu.swift:109`, `UIMenuTable.swift`): a selector
  with no row is refused as `unclassified`, so AppKit's injected items and any item added
  after the inventory are refused until the inventory and the table read them; H1/H2 fail
  until both are written.
- `newProject:` is reclassified `window` → `modal` (`inventory.json`, its `code` now
  `AppDelegate.swift:166, :170`), so New Project is refused.
- `cancel_sheet` (`AgentServer+MenuItem.swift:101`) is a tool the road map did not name; it is
  how the proof closes what it opened.
- `perform_menu_item` with no `path` lists every leaf (`AgentServer+MenuItem.swift:49`).
- The proof is a new `v2_menu.py`, not an extension of `v2_snapshot.py`.
- A path names the title the menu SHOWS after validation, so Edit ▸ Undo is "Undo Add
  Marker" once there is something to undo; R1 reads the Undo item's path from the listing
  (`v2_menu.py:454`) instead of the spec's literal `["Edit", "Undo"]`, which the first full
  run refused as `not found`.
- H3 holds each refusal to the probe's OWN table (`v2_menu.py:288`), and H4's table
  control subtracts any difference already present (`v2_menu.py:301`), so M5 fails exactly
  H1, H2 and N1 as the spec names; before that change M5 failed H4 too.
- A perform whose `sendAction` answers false is refused ("nothing handled it",
  `AgentServer+MenuItem.swift:68`), a refusal the spec's list did not name; it is what M2
  hits.
- `v2_menu.py`'s `guarded` (`:565`) fails a letter's remaining rows by name when a call
  throws, so a mutant run still prints every row, `scores:` and `digest:`.
- M3 was made by always taking the ungrouped branch (`guard …, document == nil`) and M4 by
  an always-true first line in `isEnabled`; each is the mutant the spec names.

**Review.** litecode, full route, with no fix passes. The adversary raised no objections. It
noted one unevidenced risk: a sheet still attached while it animates closed could end the
settle early. No run showed it; every `cancel_sheet` answered with no sheet attached, in
129–158 ms. The review passed with no blockers and two nits, both listed under Owed.

**Owed.**
- A row for a sheet that arrives AFTER the action returns (Speed… / Paste's reverse progress
  sheet needs rendered media): the settle covers it by design and nothing here measured it.
- The V1 spike's I rows read the grown inventory (46 sites, `newProject:` modal) and were not
  re-run; V1's record above still quotes 41 sites and one `modal` selector, as it measured.
- `UIMenu.swift:151`: `target(for:)` takes an item's explicit `target` without asking
  `responds(to:)`, so an item AppKit would disable passes `isEnabled`. The perform's "nothing
  handled it" refusal catches it afterwards, not before (review nit).
- `UISheet.swift:68`: a file panel with no `sheetParent` returns nil, and `cancel_sheet`'s
  refusal (`AgentServer+MenuItem.swift:113-118`) then talks about an Escape button and a
  button count, which does not describe a file panel (review nit).
- The `CLAUDE.md` lines listed in the implementation notes were applied by hand: `app/CLAUDE.md`'s
  four map entries and two edits, and root `CLAUDE.md`'s dev-tool paragraph under "Seeing the
  chrome".
