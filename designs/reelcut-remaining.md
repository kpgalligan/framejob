# Reelcut — what is left

**Status: road map 2 is complete** — all ten phases done, `designs/reelcut-roadmap-2.md`
§1 carries the commit of each. `make test` is at 494, `make lint` and
`cargo fmt --check` are clean, `make typecheck` is at 0 errors and its four
deliberate AVFoundation warnings, and every proof script passes: 66, 85, 121,
8, 84, 88, 167, 92, 79, 184 over MCP and 26, 33, 59, 81, 70, 78, 150, 48
offscreen.

This file is the honest remainder. Nothing in it is a feature; it is the debt
two large phases left behind, plus the checks no script can make. It is
written to be picked up cold, so each item names the files, the seam and the
test rather than the intention.

Three rules from `designs/reelcut-roadmap-2.md` §0 govern everything here and
are not restated per item: a file at the ~600-line cap gives something up
BEFORE it takes anything on; frozen files take wiring only; and a claim about
a frame is a byte comparison or it is not a proof.

---

## 1. Two fixes shipped without a permanent proof

**This is the only item where the project's own standard was not met**, and it
should be done first. Phase 9's fix wave produced two instruments that measured
their fixes and were then left untracked, so the fixes are correct and the
evidence for them is not in the tree. A fix with no permanent proof is the
shape this repository does not accept — road map 2 §5 says so in as many words.

### 1a. The marker-scope refusal has 29 checks in `tools/proof/work/`

`tools/proof/work/lane9_marker_scope_mcp.py` (159 lines, 29 checks, passing)
measures phase 9's two MCP-coherence fixes:

- `add_marker` and `set_marker`-with-a-time are REFUSED when the scope was
  inherited from `set_scope` rather than asked for, because a marker is at
  project time and the playhead inside a nest is not;
- `editResult` reports the scope the ops were actually STAMPED with, and names
  any op that went to the document under `document_ops`.

`tools/proof/work/` is git-ignored, so none of it is tracked.

**The work**: fold it into `tools/proof/phase9_proof.py` as a new section.
That file's shape is a `*_part(mcp)` function per section plus a `section(...)`
line in `main()`; the existing sections run 0–9 and end with
`limits_part` ("the documented limits, pinned so a change is noticed"), which
is where these belong or immediately before. The script takes a port argument
and its checks clean up after themselves, so the fold is mostly mechanical —
but re-measure rather than trusting the 29, because `phase9_proof.py` builds
its own fixtures and the numbering of ids will differ.

**The gate**: `phase9_proof.py` goes from 184 to 184 + N and still passes; then
break the two fixes on a COPY of the tree and watch the new checks fail. The
refusal mutant is `AgentServer+Scope.swift`'s `checkDocumentLevelTicks` made a
no-op; the landing mutant is `scopeLanding` replaced by the old unconditional
`if let scope = effectiveScope(document)`.

### 1b. The breadcrumb has never been photographed by a tracked script

`tools/proof/work/phase9-corner-probe/` holds `main.swift` (326 lines),
`build.sh`, `build-before.sh`, `build-harness.sh`, a reverted `before-src/`
tree and before/after PNGs. It builds a bare `TimelineView`, feeds it a
snapshot, SCROLLS it and captures through the same `cacheDisplay` path the
harness uses — which is what caught a z-order defect eight phases old, and what
no tracked script can currently see.

**Why the shared harness cannot do it as it stands**: every harness render is
at scroll 0, and the header column and the floating ruler do not overlap until
the pane is scrolled. So a `scope` argument alone would not have caught the
defect or proved the fix.

**The work**, and there are two honest routes — pick one and say which in the
script's docstring:

1. **A `phase9_chrome.py` over a probe**, which is what the corner probe
   already is. It needs no change to the shared instrument, and it can also
   drive `beginGesture` with real click counts and read
   `validateNestScopeAction`, which a photograph cannot. This is the cheaper
   route and the one the lane recommended.
2. **Two appended harness arguments** — a nest path or scope (so
   `TimelineView.breadcrumb` is set at all; it is view state no package
   carries, exactly `candidateSpans`' case) AND a vertical scroll offset in
   points. Append them after `mediaFilter`, in the shape `candidateSpans` and
   `expandSections` were added, so every earlier chrome script's argument
   positions still hold — then re-run phase2 through phase8_chrome.py and show
   26, 33, 59, 81, 70, 78, 150 unchanged, which is the claim that the
   appending cost nothing.

**The gate either way**: the corner at a non-zero vertical scroll, with a trail
and without one, byte-compared; and the pre-fix build must fail it. The lane
measured the digests — scrolled, before the fix the corner equalled the
NO-TRAIL corner byte for byte (the defect); after it equals the at-rest corner.

---

## 2. Two live defects, found and deliberately left

Both were found by a lane that did not own the file, reported rather than
fixed — the correct call at the time, and now nobody's.

### 2a. `generateCaches`'s doc is false, and three places repeat it

`ProjectDocument.swift:771-773` says "Safe to call repeatedly — a cache already
on disk is not rebuilt". **Measured false.** `MediaImporter.generateCaches`
(`MediaImporter.swift:385`) detaches straight into `thumbnails` then `peaks`,
and neither asks whether the cache exists — `thumbnails` tests only
`media.hasVideo` and re-decodes the whole filmstrip through `writeJPEG`, which
overwrites; `peaks` tests only `hasAudio` and re-reads the audio track. A
second call moved an existing `cache/thumbs/1/0.jpg`'s modification date by
exactly the gap between the two passes.

Nothing is corrupt — the pass is detached at utility priority and the caches
are regenerable — so this is **wasted decoding and a wrong comment, not a wrong
picture.** But there are ten call sites (`grep -n "generateCaches()"`), and
`RelinkSheetController.swift:152-154` repeats the claim verbatim as its reason
for calling it.

**The work**: either correct the doc in both places, or add an existence check
at the head of `thumbnails` and `peaks`. **The second is a behaviour change and
wants its own thought**: a half-written filmstrip from a cancelled import would
then never be completed, which is what `MediaImporter.generateCaches`'s own doc
leans on today. Decide, and write the decision where the function is.

### 2b. `CaptionExporter`'s bare `deletingPathExtension`

`CaptionExporter.swift:397` and `:438` strip an extension unconditionally, so a
caption file named `Board v1.2` loses the `.2`. `FrameWriter.renamed`
(`FrameWriter.swift:300-306`) is the fixed version of exactly this — it strips
only a KNOWN extension and falls back on an empty stem — and nothing points
those two sites at it.

**The work**: one call each, or the same guard inline. `FrameWriter.renamed`'s
`knownExtensions` is about image containers, so the caption side wants its own
`{srt, vtt}` set rather than a shared one — say which you did and why.
This has been recorded since phase 7 and is the oldest item in this file.

---

## 3. The size debt, which grew this session

29 files are over the ~600-line cap. Most are long-standing; these five are
what phases 8 and 9 moved, and the first three are AT or just past a cut that
the next feature must pay:

| File | Now | Note |
|---|---|---|
| `AgentServer+Scope.swift` | 592 | ON the cap. Seam: the envelope rule (`checkCallScope`, `effectiveScope`, `idScope`, `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` THE TOOL and its path arithmetic (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`, `scopeReport`) |
| `AgentCatalog.swift` | 807 | Was cut to 665 in `b410125` and phase 9 put it back over. **The next cut is named in the file's own header** (`:32-38`): the FILE groups — Media, Captions, Rendering, export — to an `AgentCatalog+Files.swift`, ~300 lines, sharing no hoisted local with what stays |
| `ReelOps.swift` | 925 | Created by `b410125` at 853. It is a TABLE — one factory per row of `edit.rs`'s op table — so it has the same standing exemption `edit.rs` has on the Rust side. Worth a sentence in the road map rather than a cut in a feature phase |
| `ProjectDocument.swift` | 1332 | 1045 before phase 9. Stored properties cannot move to an extension; the natural cut is the media/reverse machinery, NOT the scope |
| `TimelineView.swift` | 1625 | Frozen. 1540 before. Of phase 9's additions, four lines are code |

`ExporterWriter.swift` (1114) has been over since phase 7 and its seam — the
settings/encoder half — is still unpaid.

**None of this is work on its own.** It is the list a feature phase consults so
it pays the toll first and alone, the way `d69de99` and `b410125` did.

---

## 4. What only a person at the machine can check

These are not tasks so much as a list to run through at the machine once. The
first two have been owed since M1 and spec §10 records them; phases 8 and 9
added the rest.

- **A clip plays with audio** (spec §10 step 4) and **the preview holds 60 fps**
  (step 5). No still frame can answer either.
- **The two preview windows show the same frame.** Phase 8 measured that two
  `AVPlayerLayer`s on one `AVPlayer` both display, and that they hand back
  byte-identical `displayedPixelBuffer`s — but nothing has ever opened the
  preview window in the running app and LOOKED at the two pictures together.
  Note before reaching for an instrument: `isReadyForDisplay` and `videoRect`
  are useless here, since a detached layer and a layer in a never-shown window
  both report `true` with a plausible rect.
- **⇧⌘P, ⌘↓ and ⌘↑ from a real keyboard.** The probes drive
  `validateNestScopeAction` and synthesise `NSMenuItem`s; nothing goes through
  AppKit's menu dispatch from a real key event.
- **A nest PLAYS once open** — the scoped composition's audio and its frame
  rate. `render_frame` is a still.
- **Whether Preview Quality is actually FASTER.** Section 5 of
  `phase8_proof.py` proves the player is asked for a smaller buffer; a render
  size is not a frame rate, and nobody has measured a frame time at any
  quality. Note the shadow passes do NOT get cheaper — `shadowSilhouette`
  allocates at canvas size — so the saving is not a clean 4×.
- **`phase8_chrome.py` needs an unlocked console** for section 4's six dispatch
  checks. They score 150/150 with the screen unlocked and fail on their own
  precondition when it is locked. That is the script refusing to pass
  vacuously, not a defect.

---

## 5. Where a third road map would start

`designs/reelcut-roadmap-2.md` §4 is the list of what was deliberately left
out, and it stands. One of its conditions has now been met and the bullet
should be read in that light: **"a left-hand media browser with bins — phase
8's search and sort come first"** — they have landed, so spec §11's trigger (a
library that has outgrown the pane) is the only thing still gating it.

The others, unchanged: voice-over recording (one session, and the user's call
since spec §1 excludes capture); speed ramps (feasible, unasked — `speed` is
not an action target and the model, the plan and the audio envelopes would all
have to learn); and the explicit non-goals — LUTs, motion blur, stabilisation,
optical-flow retiming, auto-reframe, multicam, plugins, other platforms.

---

## Suggested order

1. **§1a**, then **§1b** — the only items where something shipped without the
   evidence this project requires, and §1a is an afternoon.
2. **§2b**, which is one call site and has been waiting since phase 7.
3. **§2a**, once somebody has decided whether the cure is a doc or a check.
4. **§3** is consulted, not done.
5. **§4** whenever there is a person at the machine; it is the only list here
   that cannot be closed by writing code.
