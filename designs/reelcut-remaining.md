# Reelcut — what is left

**Status: road map 2 is complete, and the debt it left is paid.** All ten
phases are done and `designs/reelcut-roadmap-2.md` §1 carries the commit of
each. **On the day it closed** `make test` was at 494, `make lint` and
`cargo fmt --check` were clean, `make typecheck` was at 0 errors and its four
deliberate AVFoundation warnings, the catalog was 75 tools and the parity log
empty, and every proof script passed: 66, 85, 121, 8, 84, 88, 167, 92, 79,
214 and 79 over MCP and 26, 33, 59, 81, 70, 78, 150, 48, 62 and 141
offscreen. Those counts are that day's; §3 is the part of this file that is
kept current.

This file was written as the honest remainder when the road map closed: the
debt two large phases left behind, plus the checks no script can make. §1 and
§2 were that debt and are now CLOSED; they stay here as the record of what
closed them, because each one taught something the next reader should not
have to relearn. §3, §4 and §5 are what is still open, and none of them is a
task with a diff at the end of it; §6, added 2026-09-19, was the one that
was, and its diff landed the same day.

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

Every file over the ~600-line cap as of 2026-09-18 — 29 of them, the
list regenerated row by row against `wc -l` at road map 7's D3·6, which
closed deepening D3. `core/src/edit_track.rs` came off it at D2·3
(674 → 522, `edit_canvas.rs` cut out of it) and nothing has joined since.

**What deepening D3 did to this list**, measured against `main` rather than
summed from the tickets (road map 7 §7–§9). `core/src/edit.rs` lost its
Arguments column, **895 → 838**: still over, and still exempt for the
SEMANTICS table that is the rest of it. That column is now data in two new
core modules, both under the 400-line cap for a new module and neither taking
`edit.rs`'s exemption — `core/src/op_table.rs` (**325** of 400) and
`core/src/op_schema.rs` (**173** of 400). On the app side the five catalog
files went **2251 → 2125** together as the structure they used to hand-write
moved to the core: `AgentCatalog+Clips.swift` **941 → 791**, the first time an
over-cap file here has come DOWN without anything being moved out of it;
`AgentCatalog+Files.swift` 609 → **601** (over by one line);
`AgentCatalog+Transitions.swift` 112 → **92**; `AgentCatalog.swift`
472 → **524**, which took `opTool` and ten argument descriptions the fifth
part of the parity check turned from a silence into a complaint; and
`AgentCatalog+Audio.swift` **117**, untouched, its two tools having no op
behind them. Three new app files stand against that, all under the 400-line
cap: `app/Sources/AgentCatalog+Declarations.swift` (**313** — the fourteen
rows where a tool deliberately takes more or less than its op, with a reason
each), `app/Sources/AgentServer+Parity.swift` (**183** — the fifth part and
nothing else) and `app/Sources/ReelOpSchema.swift` (**27**).
`AgentServer.swift`, frozen, is **771 → 774**: twelve lines of doc comment
taken across D3·3 and D3·4 and nine given back at D3·5, when the two
paragraphs describing the gap that part has now closed stopped being true.
Then **774 → 785** at kpgalligan/reelcut#21: the argument gate's two wiring
lines in `start()` and `dispatch`, and the comments saying that a call's keys
are now checked and that a stray `scope` is refused rather than ignored. The
gate itself is `app/Sources/AgentServer+Gate.swift` (**101** of 400);
`AgentServer+Arguments.swift` is 445 → **458** for the exact whole-number
read and `AgentServer+Parity.swift` 183 → **186** for the envelope list the
two files now share.
`ReelCore.swift` is **1500 → 1542** and stays where it was in this list — it
is over the cap, so only the part that had to be there went in, the function
naming `rc_op_schemas`, and the value type it answers went to
`ReelOpSchema.swift` instead.

**What road map 7 §10's phase A did to it** (2026-09-19, measured with
`wc -l` against `47db3ae`). The source-window module is a PURE MOVE, so the
test is that every file it touched came down. `core/src/model_query.rs`
**503 → 440** and the three readers, the mover, the bound and the two tail
readers are `core/src/source_window.rs` (**251** of the 400-line cap for a
new module). Every caller shrank because it stopped restating the
arithmetic: `core/src/edit_clip.rs` **1036 → 1021** (the one row of the table
below that moved, and still over the cap and still the largest Rust file),
`core/src/edit_edge.rs` 220 → **197**, `core/src/edit_split.rs` 210 → **195**,
`core/src/edit_transition.rs` 586 → **572**, `core/src/evaluate.rs`
594 → **588**, `core/src/edit_time.rs` 560 → **555**, and
`core/src/edit_canvas.rs` **241**, unchanged to the line. The one file that
grew is `core/src/lib.rs`, 83 → **84**, which is the module declaration.
`app/Sources/Transcriber.swift` stays **934**: phase A changed two of its
comments and nothing else. Nothing came off this list and nothing joined it.

**What §10's phase B did to it** (2026-09-20, `wc -l` against the tree as
phase B found it — phase A's, uncommitted). Phase B is a FEATURE, not a
move, so the test is the opposite one: no file over the cap took anything
on. `core/src/edit_clip.rs` is **1021**, unchanged to the line — the four
call sites that now read the module cost lines and `whole_media_length`'s
and `set_speed`'s own prose gave the same number back, since the module
states the arithmetic they used to restate. The catalog file
`app/Sources/AgentCatalog+Clips.swift` is **792**, unchanged to the line for
the same reason, two tool sentences rewritten inside their own wrapping.
Under the cap:
`core/src/source_window.rs` 251 → **396** of its 400-line cap, which is the
warning for the phase after this one; `core/src/edit_paste.rs` 596 →
**599**; `core/src/edit_background.rs` 468 → **479**;
`core/src/edit_nest.rs` 323 → **326**; `core/src/evaluate.rs` 588 → **591**
(a comment); `core/src/edit_canvas.rs` 241 → **236**;
`core/src/edit_transition.rs` 572 → **571**; `core/src/edit_edge.rs` and
`core/src/edit.rs` unchanged at **197** and **838**. The two new test files
are `core/tests/source_invariant.rs` (**360**) and
`core/tests/source_edges.rs` (**176**), both under the 400-line cap for a
new file. `app/Sources/ReelOps.swift` is 1131 → **1144**, a doc comment on
`setSpeed` and one on `addBackground`; it is an exempt table and the row
below is updated. Nothing came off this list and nothing joined it.

**What §10's phase C did to it** (2026-09-20, `wc -l` against the tree as
phase C found it — phases A and B's, uncommitted). Two files over the cap
took nothing on: `app/Sources/ReverseRenderer.swift` is **1311**, unchanged
to the line — its two subtractions now call `ReverseMirror` and the prose in
its type doc and in `walkBackwards` that used to restate the mirror gave the
three lines back — and `app/Sources/Transcriber.swift` is **934**, one
`private` removed so a probe can pin `project(_:in:)`.
`app/Sources/ReelOps.swift` is 1144 → **1143** (one sentence deleted from
`setSpeed`, which is no longer true). The FROZEN
`app/Sources/TimelineView.swift` is 1644 → **1652**: `sourceTime` gained the
`in media:` parameter, the reversed arm and the five lines saying why, which
is the dispatch that file holds. The new file is
`app/Sources/ReverseMirror.swift` (**88** of the 400-line cap for a new one).
`app/Sources/SpeedSheetController.swift` is 219 → **246** and
`app/Sources/MediaPeaks.swift` 236 → **228**, both well under. Nothing came
off this list and nothing joined it.

**What the E1 reader review did to it** (2026-09-20, road map 5 §12). **Toll
T was paid**, a pure move landed and gated alone by `make test` and
`make lint` before any fix touched the file: `add_transition_by_shift` and
its doc comment left `core/src/edit_transition.rs` for a new
`core/src/edit_transition_shift.rs` (**114** of the 400-line cap for a new
file), taking the three `edit_time.rs` imports with them, and the file went
571 → 477. The review's three `add_transition` fixes then took it to
**530**, still 70 under. `app/Sources/EditorViewController+Inspector.swift`
is 340 → **381**, under the cap: `shiftingOps` and its doc. Two new test
files at or under the 400-line cap:
`core/tests/add_transition_edges.rs` (**400**, AT the cap after the review's
fix pass added the short-pair rows — it gives something up before it takes
anything on) and `core/tests/crossfade_edges.rs` (**337**). Nothing came off this list and
nothing joined it.

Regenerate the list with
`wc -l app/Sources/*.swift core/src/*.rs | awk '$1>600 && $2!="total"' | sort -rn`
rather than trusting the numbers here; the standing exemptions are
`core/src/edit.rs` and `app/Sources/ReelOps.swift`, which are TABLES with one
row per op.

| File | Lines |
|---|---|
| `app/Sources/ProjectSnapshot.swift` | 2516 |
| `app/Sources/InspectorPane.swift` | 1665 |
| `app/Sources/TimelineView.swift` | 1652 |
| `app/Sources/ReelCore.swift` | 1542 |
| `app/Sources/VideoPane.swift` | 1411 |
| `app/Sources/Compositor.swift` | 1391 |
| `app/Sources/ProjectDocument.swift` | 1352 |
| `app/Sources/ReverseRenderer.swift` | 1311 |
| `app/Sources/ReelOps.swift` | 1143 |
| `app/Sources/EditorViewController.swift` | 1123 |
| `app/Sources/ExporterWriter.swift` | 1114 |
| `app/Sources/PreviewCanvasView.swift` | 1104 |
| `app/Sources/CanvasSessions.swift` | 1088 |
| `app/Sources/OptionControls.swift` | 1081 |
| `core/src/edit_clip.rs` | 1021 |
| `app/Sources/Transcriber.swift` | 934 |
| `app/Sources/AudioDSP.swift` | 890 |
| `app/Sources/AgentServer+Clips.swift` | 847 |
| `core/src/edit.rs` | 838 |
| `app/Sources/AgentCatalog+Clips.swift` | 792 |
| `app/Sources/AgentServer.swift` | 785 |
| `app/Sources/FFmpegRewrap.swift` | 768 |
| `app/Sources/Loudness.swift` | 742 |
| `app/Sources/ExportSheetController.swift` | 639 |
| `app/Sources/Exporter.swift` | 609 |
| `app/Sources/ClipPane.swift` | 609 |
| `app/Sources/MediaImporter.swift` | 604 |
| `app/Sources/CompositionBuilder.swift` | 601 |
| `app/Sources/AgentCatalog+Files.swift` | 601 |

The notes below are from road map 3's close and name each file's SEAM, which
is what a phase needs before it pays; the counts in them are as of that day.
Road map 3 paid three tolls — `AgentCatalog.swift` first and alone (R1·toll),
then `MediaImporter.swift` and `AgentServer+Recording.swift` mid-fix-wave
when a fix took each over its line — and left two files AT the cap:

| File | Now | Note |
|---|---|---|
| `AgentServer+Scope.swift` | 592 | ON the cap. Seam: the envelope rule (`checkCallScope`, `effectiveScope`, `idScope`, `addressed`, `checkDocumentLevelTicks`, `scopeLanding`, `scopeFailure`) against `set_scope` THE TOOL and its path arithmetic (`setScope`, `nestScopePath`, `pathToClip`, `applyNestScope`, `commonPrefix`, `scopeReport`) |
| `MediaImporter.swift` | 571 | Went to 619 when road map 3's held tail landed in it, and paid mid-wave: the await-free half — `ImportError`, `isImage`/`probeImage`, the rate table — to `MediaImporter+Probe.swift` (121), a pure move (619 → 518, 571 with the tail). The next cut is the peaks reader, which awaits and stays |
| `AgentCatalog.swift` | 454 | Was cut to 665 in `b410125`, phase 9 put it back over at 807, and road map 3's R1·toll paid the cut the file's own header had named, first and alone: the FILE groups — Media, Captions, Rendering and export — are `AgentCatalog+Files.swift` (**609** with `record_screen`'s entry — over the cap since R2 hoisted the entry's pause and result paragraphs into two locals for the type checker's budget; the cut it owes is that entry's sentences, whose description is the longest in the catalog; the cut it will owe is that entry's sentences), spliced after the Canvas group as the clip rows are. The header's "sharing no hoisted local" was false by ONE, `ticks`, which `fileTools(ticks:)` takes as an argument |
| `CompositionBuilder.swift` | 601 | AT the cap since road map 3's held tail (+83); the next addition pays first — the audio-parameter half (`audioParameters` and the `AudioTap.make` call) is the natural cut |
| `ReelOps.swift` | 925 | Created by `b410125` at 853. It is a TABLE — one factory per row of `edit.rs`'s op table — so it has the same standing exemption `edit.rs` has on the Rust side |
| `ProjectDocument.swift` | 1348 | Stored properties cannot move to an extension; the natural cut is the media/reverse machinery, NOT the scope. `ProjectDocument+DisplayStem.swift` is the shape a pure addition takes meanwhile; road map 3 added ONE internal method (`adoptImported`, +12 lines) so `ProjectDocument+Recording.swift` could build the untitled document by File ▸ Open's own spelling |
| `TimelineView.swift` | 1652 | Frozen. Of the five lines the cache marker added, one is behaviour (the hit-clearing under `replaced`); the marquee's `.outside` case and `beginMarquee` added fourteen net on 2026-09-19, and road map 7 §10's phase C eight more for `sourceTime`'s reversed arm on 2026-09-20 — the dispatch the file says it holds |
| `ExporterWriter.swift` | 1114 | Over since phase 7; its seam — the settings/encoder half — is still unpaid |
| `AgentServer+Clips.swift` | 1196 | Over since phase 6. Road map 7's D1·3, D1·4 and D1·5 took it to **847** by deleting what the agent door used to check by hand — the last of it `checkActionPatch`, `checkVideoEnums`, `checkTextEnums`, the three per-group key sets and the region reader. D1·6 took the shared launder out of `AgentServer+Arguments.swift` (562 → **445**, under the cap and not in the list above), so the whole `AgentServer*` family is **617 lines smaller than before D1**. The seam still unpaid here is the clip-placement handlers against the property doors |

**What the E2 reader review did to it** (2026-09-20, `wc -l`; road map 5
§12). Six product files were touched and NONE joined the list. In the core,
`motion.rs` **456 → 483** (nine lines of module doc and four of arithmetic
for the reduction's own 360, then fourteen more when the fix pass widened
that reduction to a chosen band under a whole turn — chosen, NOT a
consumer's precision; road map 5 §12's closing block — then **491** when the
residue run restated the reason) and `edit_props.rs` **328 → 356** (the
`normalise_and_check_group` the paste side has no room to hold), then
**363** when the residue run restated its doc comments; the paste
side itself paid nothing, because the fix was a one-line call swap and
`edit_paste.rs` is **599, unchanged** — the "one line of room" file stayed
at one line of room, which is the whole point of putting the body next to
`check_group`. In the app, `EditorViewController+Motion.swift` **151 →
176**, `EditorViewController+ZoomRegion.swift` **482 → 502** and
`TimelineClipDrawing.swift` **450 → 454**, all well under. One new test
file, `core/tests/motion_edges.rs` (**285**, then **370** for the fix pass's
seventh test, then **375** when the residue run restated the reason, of the
400-line cap a new file gets), and `tools/proof/e2_chrome.py` **901 →
1138**, then **1233** when the residue run added N·1's two extremes rows,
which is a proof script and not held to the cap
(`designs/reelcut-roadmap-7.md` §2.4).

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
- **The recorder, road map 3** — what no headless proof can see: the
  picker's window mode presenting from the non-activating panel and the
  choice arriving (`didUpdateWith`, a nil stream); the countdown's look;
  that a recording of a display does NOT contain the panel (the programmatic
  filter excludes Reelcut — measured at 99 % of an excluded app's pixels)
  and whether a PICKER-made recording does (R0 q3 is unmeasured and, since
  R2's decision 7, moot for the panel — it is off screen for every source);
  that the timeline's own playback is absent from the
  file (`excludesCurrentProcessAudio`); the menu bar's own screen-recording
  indicator naming Reelcut, and its Stop landing the file; the popups and
  switches working on a `.nonactivatingPanel` while another app is
  frontmost; the microphone grant prompt from the signed bundle (the
  entitlement and the usage key together); and the first shareable-content
  call of a fresh instance, which held the main thread ~37 s on a locked
  console when made through `onMain` and now runs off it. **R2's pause
  (2026-09-12)**, on the same terms: the status item's menu reading Pause
  Recording / Stop Recording, then Resume Recording / Stop Recording once
  paused, and the label switching between the coral dot and the pause
  glyph with the time FROZEN; that the system's own screen-recording
  indicator stays up through a pause (the stream keeps capturing — R0 q7
  measured 57 fps while paused, but no headless proof can see the menu
  bar); that the panel is gone from the moment the recording starts for a
  DISPLAY source too, and comes back only when the landing has a note; that
  ⌘Q while paused opens the item's menu; and
  a paused recording played back across its segment boundary in the
  timeline, where the cut between two touching clips should be invisible
  but for the paused span.
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
  checks — the only rows in this suite that need a KEY WINDOW, and a process on
  a locked console cannot activate to have one. The script no longer fails them
  there: it reads `IOConsoleLocked` and SKIPS the six by name, so the score
  reads **150/150** unlocked and **144/144 with 6 skipped by name** locked
  rather than 144/150 and six failures that looked like a regression. The skip
  is honest and not a pass — those six are simply UNMEASURED on a locked
  machine, which is why they are listed here: only a run at an unlocked screen
  asks them at all.
- **Remove Silences judged by VOICE, listened to** — road map 4 §4h's three,
  now that §4g's instruments have landed and the reader review has widened
  them (`silence2_proof.py` 91/91, `silence2_probe.py` 76/76, 2026-09-20,
  after the second sceptic pass's residue was closed; 83/83 and 65/65 after
  the sceptic's pass over that review, 79/79 and 65/65 at the review's close,
  and 61/61 and 61/61 when they landed on 2026-09-19): a narrated screencast recorded by
  the app's own recorder with the microphone on, run through Voice mode with
  the truth marked BY EAR and the spans compared, which q7 is the reason for
  — the one real mixed recording in hand defeats both VADs and nobody has
  listened to it; a cut heard across a voice-mode boundary, to say whether
  60–100 ms of offset lag plus 0.1 s of padding is breathing room or a
  clipped word, and whether the padding default should drop to 0.05 s; and
  the sheet's note when one file is PENDING while another is judged by
  level. The probe reads that note's two halves separately and scores each,
  but it has never put both on screen at once and nobody has looked at the
  sentence they make together.
- **The band from below the lanes, with a real mouse.** `marquee_probe.py`
  (2026-09-19) drives `TimelineView`'s three gesture entry points with
  synthetic points and shows the room below the lanes is inside the
  content view's frame, so a real press there reaches the same hit test;
  nobody has yet pressed a mouse there in the running app and watched the
  band draw and the selection block count up.
- **Transitions and motion, watched and heard** — road map 5 §4g's and
  §6g's checks, now that §4e's and §6e's instruments have landed
  (`e1_proof.py` 99/99, `e2_proof.py` 61/61, `e1_chrome.py` 21/21,
  `e2_chrome.py` 35/35; all four are at their post-review counts of
  2026-09-20, road map 5 §12 — E1's review moved `e1_proof.py` and
  `e1_chrome.py`, E2's took `e2_chrome.py` from 24/24 to 33/33 and its
  residue run of 2026-09-20 to 35/35, with the four N·1 rows, the two N·2
  rows, the two N·3 rows, the per-clip write and its undo control, and the
  strip's `hasPixels` gate — and `transition_sheet_probe.py` is 39/39).
  §4g: a crossfade across a Remove
  Silences cut sounding even rather than dipped or bumped; an eased push
  FEELING better than the linear one; the Transition submenu at a hard cut
  doing what a person expects; and the three wipes reading as the direction
  their names say — the proof measures which SIDE the incoming colour is on
  and where the boundary sits, which is not the same as "it reads as up".
  §6g: whether each preset's numbers look right at ordinary clip lengths
  (the tables in §5b are starting points, not measurements); whether `pop`'s
  overshoot reads as a pop; that the Preview button loops the clip; whether
  a drag begun mid-motion is tolerable, since the inspector and the canvas
  see the clip UN-MOVED while the picture moves; and that the wedges read at
  S, M and L track heights — `e2_chrome.py` measures them at M only. Two more
  since the E2 reader review measured what no row reaches (road map 5 §12,
  R4·1 and R4·2): whether a `spin` turns the way the table says it does on
  screen — no MCP row can see the DIRECTION, because a card's bounding box is
  the same at +45° and −45° — and whether a slide on a clip INSIDE a nest
  leaves by the nest's own edge rather than the project canvas's.
- **The Keychain prompt road map 6's spike met and could not read**
  (`designs/reelcut-roadmap-6.md` §3 q7, run 2026-09-20). A login-keychain
  item added by one ad-hoc-signed build and read by the NEXT one — a
  different cdhash, which is what every `make app` produces — blocked on a
  `SecurityAgent` modal for the whole twenty-second bound, with
  `kSecUseAuthenticationUIFail` set and not honoured, and its DELETE answered
  `errSecInvalidOwnerEdit`. Nobody was at the machine to read the dialog. A
  person can: what does it say, does "Always Allow" survive a rebuild, and
  does a build signed with a stable Developer ID identity avoid it entirely?
  The answer decides whether C1's `0600` file (§5d) can ever go back to being
  a Keychain item. The spike left NOTHING in the Keychain —
  `com.reelcut.spike.q7` was deleted and verified gone on both keychains, and
  `com.kgalligan.reelcut.assemblyai` was never touched — so there is nothing
  to clean up, only something to look at.

---

## 5. Where a third road map would start

`designs/reelcut-roadmap-2.md` §4 is the list of what was deliberately left
out, and it stands. One of its conditions has now been met and the bullet
should be read in that light: **"a left-hand media browser with bins — phase
8's search and sort come first"** — they have landed, so spec §11's trigger (a
library that has outgrown the pane) is the only thing still gating it.

**Screen recording is BUILT, and pausable** (road map 3's R1 and R2; the record is in that file) — the
sentence below is kept as the pointer it was: `designs/reelcut-roadmap-3.md`
reverses spec §1's non-goal by a recorded decision and lays out the spike
and the one phase that builds it — built, reviewed and fixed since; its
record is in that file.

The others, unchanged: voice-over recording (one session, and the user's call
since spec §1 excludes capture); speed ramps (feasible, unasked — `speed` is
not an action target and the model, the plan and the audio envelopes would all
have to learn); and the explicit non-goals — LUTs, motion blur, stabilisation,
optical-flow retiming, auto-reframe, multicam, plugins, other platforms.

**One pre-existing defect a caller CAN reach, filed and not fixed** —
kpgalligan/reelcut#24, found by the sceptic's second pass over road map 4's
reader review and outside that diff entirely
(`designs/reelcut-roadmap-4.md` §8). A clip's `start` is bounded at ±9.0e15
**per call** (`snappedTick`, `app/Sources/AgentServer+Arguments.swift:370`)
and never cumulatively, so about 1020 successive maximum-delta `move_clip`s
walk a clip's start toward `Int64.max`. The core SATURATES and says nothing
(`core/src/edit_clip.rs:557`, `clip_end` :95); the app then TRAPS on the
same sum, `ClipSnapshot.end` being `start + duration`
(`app/Sources/ProjectSnapshot.swift:1700`), during
`TimelineView.rebuildLayout`, and the process dies. Reproduced once, by the
sceptic, 2026-09-20. It is labelled `bug` and deliberately NOT
`ready-for-agent`: **where the bound belongs is a spec §11 decision** — a
ceiling on `start` in the core's own op, refused in the rule's own sentence,
or overflow-safe arithmetic in the app, which changes nothing a caller can
see. A person picks one and records it before any code.

**Two findings of the E2 reader review, filed and not fixed**
(`designs/reelcut-roadmap-5.md` §12, R2·3 and R3·2; 2026-09-20).
**kpgalligan/reelcut#26** — `set_canvas {"fps": [24,1]}` on a 30 fps project
re-snaps every clip, action and marker time and leaves `video.motion`'s
`duration` and `period`, and `text.animation`'s two timings, exactly where
they were: on a 25,000-tick grid a stored 20,000 is sub-frame, against
`core/CLAUDE.md`'s Times rule. `paste`'s re-snap from another rate has the
same hole. Nothing renders wrong — `motion::apply` interpolates continuously
and never reads the grid — so what is broken is the invariant and what an
inspector shows. Not fixed here because the root, `core/src/edit_canvas.rs`,
was outside that review's file list and because text's timings are in the
same position; labelled `bug`.
**kpgalligan/reelcut#27** — a motion slot with `duration: 0` is legal
(`ticks_positive_or_zero`), INACTIVE in the core (`motion.rs`'s
`arrive > 0.0` filter) and LIVE in three places in the app: the strip draws
the 2 pt minimum wedge, the section shows the kind with In Duration live, and
Clip ▸ Motion checks it. **Where the answer belongs is a spec §11 decision** —
refuse 0 at the door, normalise the slot away like the all-`None` motion
beside it, or stop claiming it in the UI — and `text.animation`'s
deliberately 0-legal timings argue both ways. Labelled `bug` AND `spec`, and
deliberately not `ready-for-agent`.

**One pre-existing defect nothing can reach**, found by the probe deepening
D2·2 built and named here because that ticket said it belonged in this
document: `ProjectDocument.performGroupedEdit` opens an undo group and
balances it whatever the edit answered, so an edit that changes nothing
leaves an EMPTY group behind — a step a person would press ⌘Z twice past. It
has been true since an identity has been possible and no caller reaches it:
the agent refuses at its own trial first and the menu path does not use that
entry point. `tools/proof/refusal_probe.py` prints it as a note rather than
scoring it, so the day a caller does reach it the probe already says so.

**A second op whose tick argument is bounded only by `i64`, filed and not
fixed** — kpgalligan/reelcut#25, found by the E1 reader review
(`designs/reelcut-roadmap-5.md` §12, R1·3 and R1·6; the limit is §3j's).
`add_transition`'s step-down and `add_transition_by_shift`'s both remove ONE
frame per pass. The handle form used to walk the caller's `duration` — 4.5e11
passes and about 36 hours at the 9.0e15 the argument gate allows, from a
measured ladder — and that is fixed: the request is held to
`(A.duration + B.duration) / 3·frame`, the most the overlap rule can pass at
any split. **What is left is that the CLIPS are the caller's too.** One
ordinary `add_text_clip {duration: 9000000000000000}` makes a clip that long,
and a lopsided split over two of them walks ~6.7 hours, extrapolated from
0.181 / 1.607 / 16.134 s at d = 6e10 / 6e11 / 6e12; the run at the full value
**expired at 120 s (pid 61383 killed)**, which is its measured answer. It is
#24's family — a per-call bound with nothing cumulative behind it — and what
would close it is either a bound on a clip's DURATION at the door or a closed
form for the step-down, which needs a decision: the loop's own doc calls the
predicate "not monotone in an obvious direction", so a binary search would be
relying on the opposite. Labelled `bug`, not `ready-for-agent`.

**One HOST limit with a cost at export**, measured by `e1_proof.py` §5 and
recorded in `designs/reelcut-roadmap-5.md` §12 (2026-09-19): AVFoundation does
not apply a mix input's first volume point for some twelve milliseconds, so
the first 25 ms of an incoming clip come out at about half full scale whatever
the ramp asks for — and the same burst is there at a hard cut with the clip
MUTED, which is where the proof scores it, so nothing in Reelcut is what puts
it there. It is bigger than road map 5 §4e's own sentence expects ("one LSB
within 8 ms of a ramp edge") and it is in the exported file, not only in
preview. Nothing is filed for it and no fix is attempted here: what a later
road map could try is giving the first breakpoint a lead-in — a ramp that
starts before the clip does — and re-measuring with `e1_proof.py`'s §5 rows,
whose window 0 is printed and whose hard-cut row is what would move.

**One deepening candidate, measured and waiting — the COMMIT TAIL**
(`designs/reelcut-roadmap-7.md` §10.1, and §10.6 which decided it does not
come along with the source window). Every op in the core ends the same way,
and the honest count depends on where the block is cut: **5** byte-exact
copies, **14** `check_overlap_rule` → `Ok(Outcome::Refused(why))` guards,
**17** `set_gained_transitions` + `self.finish(next)` pairs, **12** functions
carrying both, and **10** where the guard is the pre-commit trial on `self`
rather than on `next` — **11** if `roll` is counted, which has the guard and
the finish but deliberately no `set_gained_transitions`. It shares its
functions with the source window and nothing else: it is about purity, the
overlap rule and undo, and it should be judged on that. Phase A of the source
window left every one of those tails exactly as it found them.

Three small things the closing turned up that a third road map would pick up
on its way past, none worth a phase: `relink_media` could re-probe the file
it is pointed at (§2a's recorded limit); the panel and MCP spellings of a
caption name carrying another of the app's containers could be made to agree
by a decision in spec §11 (§2b's); and `SilenceSheetController.cacheChanged` re-read on a
peaks or speech post only while something was pending, so spans an open sheet
measured from a file that an MCP `relink_media` then swapped away (the sheet
is modal, so nothing else can) stayed until the sheet was reopened — left as
a one-line guard on the belief that no proof could drive the sheet.
**Closed 2026-09-20** by road map 4's reader review (§8, R2·2): the belief was
wrong, `silence2_probe.py`'s claim 17 drives the sheet through a real document
and posts at it, the guard is gone, and two rows there swap the `.bin` under
an open sheet with nothing pending and watch the readout follow. A copy with
the guard restored scores 64/65, taking the first of the two.

Two more, found 2026-09-19 and worth a line each: `docs/agents/triage-labels.md`
names a `needs-triage` label the repository does not have (`gh label list`
shows `bug`, `spec`, `ready-for-agent` and GitHub's defaults), so a report
that needs the maintainer's eye — kpgalligan/reelcut#22 was one, closed
2026-09-19 — carries `bug` alone; either create the label or change the
table's right-hand column.
And the two frame-rate pair readers in `AgentServer+Media.swift` and
`AgentServer+Tracks.swift` still read `intValue` on each half after the
argument gate (road map 7 §11's named residue), so a fractional numerator is
truncated in silence where every other integer argument is refused by name.

**Two more, found by road map 7 §10's phase B (2026-09-20) and deliberately
left there**, both recorded in §10.8 as well:

- **`set_canvas`'s `resnap` does not re-snap clips INSIDE nests.**
  `core/src/edit_canvas.rs`'s `resnap` walks `project.clips` only, so a rate
  change leaves every nested clip on the OLD frame grid; the document is
  then a mixture, and nothing says so. Phase B's `unnest` vector is how it
  shows: a nest made at 30 fps and opened at 24 gives back clips whose
  stored times were never on the 24 fps grid, which is why `unnest` now
  re-snaps and bounds each one (spec §11, D4-4). Not fixed there because a
  rate change reaching inside nests is a document-wide edit with its own
  overlap question, and because the markers rule (`resnap` drops the second
  of two markers a coarser grid lands on one tick) would need an answer per
  nest. Found by phase B's scout and recorded nowhere before this.
- ~~**`SpeedSheetController.syncReadout`'s "→ duration" is the UN-HELD
  number.**~~ **CLOSED by §10's phase C** (2026-09-20, spec §11's D4-6).
  The readout is now the CORE's answer: `SpeedSheetController.lengths`
  applies the sheet's own `set_speed` ops to the immutable handle and reads
  the durations back, so it says the held number, the overlap rule's
  refusals and a mixed selection's sum without a second copy of the
  arithmetic in Swift and without a new `rc_*` export. What phase C
  deliberately did NOT fix is recorded in §10.9: the sheet's HINT still
  says only that a speed change opens or leaves a gap, and the readout shows
  a length rather than the cross dissolve a neighbour gains.

---

## 6. The Rust build settings, measured 2026-09-19

`core/Cargo.toml`'s one profile line, `[profile.release] lto = true`, does
NOT reach the shipped staticlib and DOES reach every test binary — the
reverse of what it is there for. Cargo passes no `-C lto` to a unit whose
crate types include `rlib` (rustc cannot LTO an rlib, so cargo skips the
whole unit), and the lib is `["staticlib", "rlib"]`; the `-v` line for the
lib carries `--crate-type staticlib --crate-type rlib -C opt-level=3
-C strip=debuginfo` and nothing else, and `libreelcut_core.a` has 437
members, 17 of them the crate's own codegen units, at 32 MB. With
`crate-type = ["staticlib"]` alone cargo does pass `-C lto=fat`, the build
takes 29.5 s instead of 11.6 s and the archive is 8 MB — and every
integration test then fails to compile (`error[E0433]: failed to resolve:
use of unresolved module or unlinked crate reelcut_core`), because a test
links the rlib. Product LTO would therefore cost a crate split (a shim crate
that is `["staticlib"]` only, over the lib crate) and eighteen seconds per
`make app`; nothing measured says the core's JSON, arithmetic and plan work
would repay it. The parent `~/devel/rasterize/core/Cargo.toml` has the same
line over the same two crate types, unmeasured there.

What the line does do is give each of the 31 integration-test binaries, and
the lib's own empty harness, a fat LTO over the whole crate graph from
bitcode, so one edit re-optimises the crate 32 times. Measured on the M2 Max
(8P+4E, 12 jobs — cargo's default `-j` and the right one), in a copy of
`core/` with one target directory per variant, wall clock in seconds:

| `[profile.release]` | cold build | build after edit | test build after edit | test run |
|---|---|---|---|---|
| `lto = true` (today; fat) | 17.4 | 11.7 | 166.3 | 6.8 |
| `lto = "thin"` | 17.4 | 11.2 | 172.0 | 6.8 |
| `lto = false` (thin-local, the default) | 16.9 | 11.6 | 26.2 | 6.7 |
| `lto = false`, `incremental = true` | 16.2 | 1.0 | 3.0 | 6.6 |
| dev profile, no `--release` | 12.1 | 1.1 | 3.2 | 9.9 |

The "after edit" columns above are a comment inserted at the top of
`outcome.rs`, which incremental hashing all but skips; with a real statement
added to `time.rs::snap_to_frame`, which the crate inlines everywhere,
`lto = false` + `incremental = true` measures 4.5 s to rebuild the staticlib,
6.1 s to rebuild every test binary and 8.7 s for the whole of
`cargo test --release`. A touched but unchanged file is the floor at 0.9 s
and 3.1 s. The other levers do not move: rust-lld through `-fuse-ld=lld`
against Apple ld-prime 1230.1 is 27.2 s against 26.2 s for the test build
(noise), and the `.a` itself is never linked on the Rust side at all;
`opt-level = 1` in dev is slower cold (19.4 s) and no faster warm;
`cargo test --doc` is 0.4 s and `[lib] test = false` saves 0.2 s; the deps
are some five seconds of a cold build, so sccache has nothing to save; the
671 tests run in under seven seconds across 31 binaries, so nextest has
nothing to parallelise yet. `panic = "abort"` is not available: `ffi_agent.rs`
catches unwinds. `make test` stays `--release`, as the rule says: the dev
profile is no faster to build and 3 s slower to run, and it would test a
configuration the app does not ship.

**LANDED 2026-09-19, uncommitted: two lines in `core/Cargo.toml`** — in
`[profile.release]` itself,
because `make rust`, `make test`, the Xcode pre-build script and
`LIBRARY_SEARCH_PATHS` all hard-code `release`, so a custom profile would
have to be threaded through four places:

```toml
[profile.release]
# No LTO: cargo skips it for a staticlib+rlib unit anyway, and asking for it
# fat-LTOs each of the 32 test binaries (166 s per edit; §6 of remaining).
incremental = true
```

That is `lto = true` deleted and `incremental = true` added; the shipped
`.a` is then codegen'd in up to 256 units instead of 16 (583 archive
members, 163 of them the crate's, 22 MB), and
`CARGO_INCREMENTAL=0 cargo build --release` is the one-off way back to 16
when a product build should be.

Measured in place after it landed: the first `make test`, a full rebuild
and run, 28.9 s, 671 passed; then with a comment line inserted at the top
of `outcome.rs` and removed again, `cargo build --release` 0.8 s and
`make test` 6.5 s and 8.6 s on two successive edits (the run itself is
~6.5 s of that), against ~12 s and ~173 s before; `make lint` clean in
2.9 s; `make app` BUILD SUCCEEDED; the built app launched on its own port
with an empty parity log, published 77 tools, and answered `new_project`
and `get_project` through the core, and the argument gate refused a
stranger key by name. The cold build is unchanged. The expectation written
above the table before the change (first run 40–50 s, then ~9 s and
1–5 s) held, and the first run was faster than expected.

---

## What is left, in order

1. **§4** whenever there is a person at the machine; it is the only list here
   that cannot be closed by writing code.
2. **§3** is consulted, not done.
3. **§5** is a decision, and the user's.
4. **§6** landed 2026-09-19 and is not yet committed.
