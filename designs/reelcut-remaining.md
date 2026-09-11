# Reelcut — what is left

**Status: road map 2 is complete, and the debt it left is paid.** All ten
phases are done and `designs/reelcut-roadmap-2.md` §1 carries the commit of
each. `make test` is at 494, `make lint` and `cargo fmt --check` are clean,
`make typecheck` is at 0 errors and its four deliberate AVFoundation
warnings, the catalog is 74 tools and the parity log is empty, and every
proof script passes: 66, 85, 121, 8, 84, 88, 167, 92, 79, 214 and 79 over
MCP and 26, 33, 59, 81, 70, 78, 150, 48, 62 and 141 offscreen.

This file was written as the honest remainder when the road map closed: the
debt two large phases left behind, plus the checks no script can make. §1 and
§2 were that debt and are now CLOSED; they stay here as the record of what
closed them, because each one taught something the next reader should not
have to relearn. §3, §4 and §5 are what is still open, and none of them is a
task with a diff at the end of it.

Three rules from `designs/reelcut-roadmap-2.md` §0 governed the closing and
are not restated per item: a file at the ~600-line cap gives something up
BEFORE it takes anything on; frozen files take wiring only; and a claim about
a frame is a byte comparison or it is not a proof.

---

## 1. Two fixes that shipped without a permanent proof — CLOSED

This was the only item where the project's own standard was not met. Phase
9's fix wave produced two instruments that measured their fixes and were then
left untracked in the git-ignored `tools/proof/work/`, so the fixes were
correct and the evidence for them was not in the tree. Both instruments are
tracked now and both untracked originals are deleted.

### 1a. The marker-scope refusal — `phase9_proof.py` section 9

The lane script had **28** `check(...)` calls, not the 29 this file said —
the 29th was `def check`, counted by a bare `grep -c`. They are transcribed
with their own wording as `marker_scope_part`, section 9 of
`tools/proof/phase9_proof.py`, before the documented limits (now section
10), with one check tightened (`msg2 == msg` passed VACUOUSLY under the
refusal mutant, `None == None`) and two the fold added: the exact text of
the wrong-typed-tick refusal, and the undo of an inherited-scope
`remove_marker` restoring the marker ON THE DOCUMENT with the nest still
open. Thirty checks; the script is **214/214**.

The gate, on copies of the tree with the app built in each:
`checkDocumentLevelTicks` made a no-op scores 209/214 and takes the five
refusal checks (its own marker lands at nest-local 0, and the `set_marker`
that follows collides with it — exactly the wrong placement the refusal
exists to prevent); `scopeLanding` replaced by the old unconditional echo
scores 209/214 and takes the five `document_ops` checks.

### 1b. The breadcrumb, photographed — `phase9_chrome.py`

Route 1 was taken — a probe compiled from `app/Sources`, not two harness
arguments — and its docstring says why: a harness render is at scroll 0 and
the defect only shows scrolled, and a photograph cannot read a click count or
a validator. **62/62.** Six scenes of a bare `TimelineView` (at rest and
scrolled, with and without a trail, a rename open and a rename ENDED), the
corner byte-compared as a decoded 264×44 px crop that prints where it
differs, and the gesture half read as the `Equatable` `TimelineHit` rather
than a string.

Two things the untracked instrument got wrong, corrected in the tracked one:
its six-track fixture was NOT scrollable — six text tracks at size index 1
are 306 pt against a 324 pt pane, so its 62 pt scroll was an unclamped
over-scroll through `NSClipView.scroll(to:)`, valid for the z-order pictures
but a state the app never reaches — and the tracked script uses ten tracks
and asserts the scroll is real; and its scenes never ENDED a rename, so a
mutant deleting `endRename`'s restore line would have survived them.

The gate is a MUTANT on a copy of `app/Sources`, and it had to be: no git
commit has the old z-order WITH a breadcrumb (phase 9's app commit ships the
fix, and its parent has neither). Init order swapped back to ruler-then-
headers scores 52/62; `endRename`'s restore deleted 57/62; the double-click
guard flipped 55/62. All three named in the script's docstring and the
README.

---

## 2. Two live defects, found and deliberately left — CLOSED

### 2a. `generateCaches`'s doc was false; now it is true

The sentence "Safe to call repeatedly — a cache already on disk is not
rebuilt" was measured false: every call re-decoded every media's filmstrip
and re-read its audio, and four comments repeated the claim. This file
offered two cures and asked for a decision. **The decision was a third
shape: a completion marker keyed to the source file's identity**, because
the doc-only cure leaves every open of a saved project re-decoding a
40-minute screencast, and the plain existence check is a WRONG PICTURE, not
a behaviour change — `relink_media` keeps the media id, so `thumbs/<id>/`
already exists with the old film's frames and a relinked media would never
get new ones, and Remove Silences and Normalize would measure the old file.

What landed (spec §5.6; `MediaCacheFiles.swift`, after a pure move took the
await-free half of the cache out of `MediaImporter.swift` first and alone,
`3e5b598`): `CacheStamp` — the source's byte size and modification second
plus the record fields and generator constants that size a cache — written
LAST by a finished pass as `thumbs/<id>/complete.json` and
`peaks/<id>.complete.json`, and carrying NO path, deliberately: the reversed
cache's digest names a file in a directory shared with other sources and
must tell them apart, while a marker sits inside one media's own cache, and
leaving the path out is what lets a moved package, a consolidated copy and a
copy on another disk keep every filmstrip. `generateCaches`'s task stats the
file once and hands the stamp to both halves; `thumbnails` and `peaks`
compare it with their marker at the head and return without decoding when it
matches; a relinked, changed, partial or unmarked cache is deleted — the old
frames, or the old `.bin`, whose withdrawal is posted at once so nothing
measures the previous file's sound meanwhile — and rebuilt, and the marker
is written LAST and only for a strip the pass can vouch for: at least one
frame landed and every frame it wrote is still there when the loop ends. The
FIRST post of a replacing pass says `replaced`, which is what lets
`TimelineView.swift` (five wiring lines) drop that media's decoded tiles only
then — a relink used to leave the old film on screen until the 800-entry
drop, pre-existing. Passes for one media run one at a time in CALL ORDER
through `CacheLedger`, an `NSLock` rather than an actor, because a pass
carries the URL the media resolved to when asked and two `Task` hops from one
thread are not ordered. The false sentence is now the true one in every
place it stood, and `MediaImporter.generateCaches`'s "a cancelled import (the
document closing)" — a case that does not exist; nothing cancels the task —
names the real partial cases: a first save mid-pass, a save of a TITLED
document mid-pass (NSDocument swaps the package and the frames written
between its listing and the swap are lost — the vouching rule is what keeps
that strip unmarked), and process death.

**The first landing passed its own gate and was still wrong twice**, which
is the sentence to keep. Its review found the titled-document save (the
marker certified the holes) and the peaks half leaving the old `.bin`
readable through a rebuild, plus a reader that fails on every frame
certifying an empty strip, an image whose decode fails posting nothing, and
`replaced` on every batch post; all fixed, each with a row that a copy
without the fix fails. The size toll came due a second time mid-fix (644
against the cap) and was paid by moving the peak-bucket arithmetic to
`MediaCacheFiles.swift` as `PeakBuckets`, its `.bin` byte-identical to the
pre-move binary's; 586 and 490 after.

Measured: `tools/proof/remaining_proof.py` **79/79** over MCP, whose
instrument is `os.stat`'s inode and nanosecond mtime across a 3 s window
against a baseline read before the trigger, bounded by a positive control
whose measured rebuild latency (0.06 s here) is asserted inside that window;
`copyItem` preserves `st_mtime_ns`, so Consolidate rebuilds nothing, which
the script asserts and prints; and a relink to a file with no audio track
withdraws the `.bin`, after which `detect_silence` reports the media pending
rather than answering from the old file. `remaining_probe.py` sections 2–5
are the app side: the stamp as pure calls (a byte copy at another path is
EQUAL), the ledger as a count of posts, the stale-tile wiring as pixels (red,
then blue), and the pass's own rules — a frame deleted mid-pass earns no
marker and a retry, an unreadable file earns none, a failed image decode
still posts, one post carries `replaced`, a withdrawal posts once. Twelve
mutants, none surviving: the thumbs head check deleted 65/69, `modified`
forced to 0 59/69, a 4 s sleep after the head check 67/69, the peaks head
check deleted 75/79, `clearPeaks` back to marker-only 76/79; the ledger
removed 107/108, the hit-clearing removed 105/108, the presence check removed
138/141, its empty-set guard removed 139/141, the withdrawal's probe half
139/141, the image post moved back 140/141, `replaced` on every post
140/141. Phases 2, 3, 3-silence and 5, whose fixtures read the peaks path,
still score 85, 121, 8 and 88.

Recorded, not fixed, beside the code: `relink_media` never re-probes, so a
relink to a file of another length sizes the new strip and the bucket count
from the old `duration`; the marker rebuilds on a relink, at the old length.
The ledger's price is that a pass stuck inside one AVFoundation call (a
stalled network volume) holds every later pass for that media, a relink away
from the stalled file included; the escape does not help a stuck call and
reintroduces the interleave for a slow one, so it was argued and not built.
And `stripHolds`' listing and the marker's write are two steps, so a swap
landing between them (one directory read wide) would still certify holes.

### 2b. `CaptionExporter`'s bare `deletingPathExtension` — and two siblings

The item's premise was half wrong, and the scout caught it before a line was
written. The format popup's site wanted the `{srt, vtt}` set this file
described — it is `CaptionExporter.renamed`, `FrameWriter.renamed`'s six
lines with `rawValue` for `fileExtension`. The other site strips the
DOCUMENT's extension off a title-bar name (`displayName`, which is
`Board v1.2.reelcut` or `Board v1.2` depending on Finder), so a caption set
there would have written `Board v1.2.reelcut.srt`; its set is `{reelcut}`,
and two siblings had the identical bare strip on the same name — Save
Frame's stem and the export sheet's `suggestedName`. All three read
`ProjectDocument.displayStem` now (`ProjectDocument+DisplayStem.swift`, an
extension because the base file is over the cap).

Both sites are PANEL-only, and the MCP path was right all along —
`export_captions` goes through `destinationURL`, which strips only a
`replaceableExtensions` member and appends otherwise — so an MCP check for
`Board v1.2` passes against the unfixed build and cannot be the evidence.
The proof is `tools/proof/remaining_probe.py`'s section 1: tables over the
three helpers (and it is the first instrument to call `FrameWriter.renamed`,
whatever that function's docstring claimed since phase 7), the instance
accessor over a live document, and a STRUCTURAL read that the four sites
actually call their helpers — because an unwired site with correct helpers
beside it scored 60/60 on the behavioural rows. Three mutants: the caption
helper reverted 59/63, the stem helper reverted 60/63, one site unwired
60/63. Recorded limit, pinned rather than fixed: a caption panel name
carrying another of the app's own containers — `chart.png` under SubRip — is
`chart.png.srt` in the panel and `chart.srt` over MCP; widening the set
would be the bare strip with a longer list.

---

## 3. The size debt

25 files in `app/Sources` are over the ~600-line cap. Most are long-standing;
these are the ones the last two phases and the closing above moved, and the
first three are AT or just past a cut that the next feature must pay:

| File | Now | Note |
|---|---|---|
| `AgentServer+Scope.swift` | 592 | ON the cap. Seam: the envelope rule (`checkCallScope`, `effectiveScope`, `idScope`, `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` THE TOOL and its path arithmetic (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`, `scopeReport`) |
| `MediaImporter.swift` | 586 | Just under the cap, after giving up the await-free cache plumbing to `MediaCacheFiles.swift` (490) twice — the pure move, then the peak-bucket arithmetic when the fixes reached 644. What is left is the probing half and the three async writers; the next cut is the probing half, and it is the half that does NOT await |
| `AgentCatalog.swift` | 807 | Was cut to 665 in `b410125` and phase 9 put it back over. **The next cut is named in the file's own header**: the FILE groups — Media, Captions, Rendering, export — to an `AgentCatalog+Files.swift`, ~300 lines, sharing no hoisted local with what stays |
| `ReelOps.swift` | 925 | Created by `b410125` at 853. It is a TABLE — one factory per row of `edit.rs`'s op table — so it has the same standing exemption `edit.rs` has on the Rust side |
| `ProjectDocument.swift` | 1336 | Stored properties cannot move to an extension; the natural cut is the media/reverse machinery, NOT the scope. `ProjectDocument+DisplayStem.swift` is the shape a pure addition takes meanwhile |
| `TimelineView.swift` | 1630 | Frozen. Of the five lines the cache marker added, one is behaviour (the hit-clearing under `replaced`) |
| `ExporterWriter.swift` | 1114 | Over since phase 7; its seam — the settings/encoder half — is still unpaid |
| `AgentServer+Clips.swift` | 1196 | Over since phase 6 |

**None of this is work on its own.** It is the list a feature phase consults
so it pays the toll first and alone, the way `d69de99`, `b410125` and
`3e5b598` did.

---

## 4. What only a person at the machine can check

These are not tasks so much as a list to run through at the machine once. The
first two have been owed since M1 and spec §10 records them; phases 8 and 9
and the closing above added the rest.

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
- **Opening a saved project is now quick.** The marker's whole point is
  that a second open decodes nothing; the proofs show the inodes do not move,
  and nobody has yet felt the difference on a long recording.
- **A relinked clip's filmstrip changes on screen.** `remaining_probe.py`
  section 4 shows the tile turn blue offscreen; the Relink… sheet in the
  running app has not been watched doing it.
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

**Screen recording is now decided and planned**: `designs/reelcut-roadmap-3.md`
reverses spec §1's non-goal by a recorded decision and lays out the spike
and the one phase that builds it. Nothing of it is built.

The others, unchanged: voice-over recording (one session, and the user's call
since spec §1 excludes capture); speed ramps (feasible, unasked — `speed` is
not an action target and the model, the plan and the audio envelopes would all
have to learn); and the explicit non-goals — LUTs, motion blur, stabilisation,
optical-flow retiming, auto-reframe, multicam, plugins, other platforms.

Three small things the closing turned up that a third road map would pick up
on its way past, none worth a phase: `relink_media` could re-probe the file
it is pointed at (§2a's recorded limit); the panel and MCP spellings of a
caption name carrying another of the app's containers could be made to agree
by a decision in spec §11 (§2b's); and `SilenceSheetController.cacheChanged`
re-reads on a peaks post only while something is pending, so spans an open
sheet measured from a file that an MCP `relink_media` then swapped away (the
sheet is modal, so nothing else can) stay until the sheet is reopened — a
one-line guard, left because no proof can drive the sheet and the tree does
not ship a fix without one.

---

## What is left, in order

1. **§4** whenever there is a person at the machine; it is the only list here
   that cannot be closed by writing code.
2. **§3** is consulted, not done.
3. **§5** is a decision, and the user's.
